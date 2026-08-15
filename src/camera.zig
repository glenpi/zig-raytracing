const std = @import("std");
const hittable_list = @import("hittable_list.zig");
const ray = @import("ray.zig");
const color = @import("color.zig");
const vec3 = @import("vec3.zig");
const util = @import("util.zig");

// Owns the viewport/basis-vector setup and the top-level render loop: for every
// pixel, fires several randomly-jittered rays (antialiasing) through the world
// and averages what they see. Configure the public fields, then call render() —
// initialize() runs automatically as render()'s first step.
pub const Camera = struct {
    // --- Public configuration, set by the caller (see main.zig) before render() ---
    aspect_ratio: f64 = 1.0,
    image_width: u32 = 100,
    samples_per_pixel: u32 = 10, // rays per pixel, for antialiasing (see getRay)
    max_depth: u32 = 10, // max ray bounces; caps recursion in rayColor()

    vfov: f64 = 90, // vertical field of view, in degrees
    lookfrom: vec3.Point = vec3.zero,
    lookat: vec3.Point = vec3.init(0, 0, -1),
    vup: vec3.Vec3 = vec3.init(0, 1, 0), // world-space "up", used to derive u/v/w

    defocus_angle: f64 = 0, // full angle (degrees) of the defocus (depth-of-field) disk; 0 = pinhole, no blur
    focus_dist: f64 = 10, // distance from the camera at which objects are perfectly in focus

    // --- Derived state, computed by initialize(). Setting any of these
    //     directly is pointless: initialize() overwrites them all. ---
    image_height: u32 = 0,
    pixel_samples_scale: f64 = 0, // = 1/samples_per_pixel, precomputed to average samples cheaply
    center: vec3.Point = vec3.zero, // camera/eye position; ends up equal to lookfrom
    pixel00_loc: vec3.Point = vec3.zero, // world-space location of pixel (0,0)'s center
    pixel_delta_u: vec3.Vec3 = vec3.zero, // world-space offset from one pixel to the next, horizontally
    pixel_delta_v: vec3.Vec3 = vec3.zero, // world-space offset from one pixel to the next, vertically
    // Camera-space basis vectors (u = right, v = up, w = backward, i.e.
    // pointing from lookat toward lookfrom), derived from lookfrom/lookat/vup.
    u: vec3.Vec3 = vec3.zero,
    v: vec3.Vec3 = vec3.zero,
    w: vec3.Vec3 = vec3.zero,
    defocus_disk_u: vec3.Vec3 = vec3.zero,
    defocus_disk_v: vec3.Vec3 = vec3.zero,

    // Sets up the virtual "viewport": a rectangle one focus_dist in front of
    // the camera, sized in world units, that maps 1:1 onto the image's pixel
    // grid. Everything here is just figuring out, for each pixel index (i, j),
    // what 3D point it corresponds to on that rectangle — that point becomes a
    // ray's target in getRay().
    fn initialize(self: *Camera) void {
        // lossyCast rather than @intFromFloat: a zero, negative or NaN
        // aspect_ratio is illegal behavior for @intFromFloat, and it would trip
        // before the @max below could clamp it back to a usable height.
        const height: f64 = @as(f64, @floatFromInt(self.image_width)) / self.aspect_ratio;
        self.image_height = @max(1, std.math.lossyCast(u32, height));

        self.pixel_samples_scale = 1.0 / @as(f64, @floatFromInt(self.samples_per_pixel));

        self.center = self.lookfrom;

        const theta = util.degreesToRadians(self.vfov);
        const h = std.math.tan(theta / 2);
        const viewport_height = 2 * h * self.focus_dist;
        // Recompute width from the *actual* image_height (which was rounded to
        // an integer) rather than reusing aspect_ratio directly, so the
        // viewport's aspect ratio matches the image's aspect ratio exactly.
        const width_f: f64 = @floatFromInt(self.image_width);
        const height_f: f64 = @floatFromInt(self.image_height);
        const viewport_width = viewport_height * (width_f / height_f);

        self.w = vec3.unitVector(self.lookfrom - self.lookat);
        self.u = vec3.unitVector(vec3.cross(self.vup, self.w));
        self.v = vec3.cross(self.w, self.u);

        // Vectors across the horizontal and down the vertical viewport edges.
        // viewport_v points -y (down) because image row 0 is the top of the
        // image but +y is "up" in world space.
        const viewport_u = self.u * vec3.splat(viewport_width);
        const viewport_v = -self.v * vec3.splat(viewport_height);

        // Per-pixel step vectors: dividing the full viewport edge by the pixel
        // count gives the world-space distance between adjacent pixel centers.
        self.pixel_delta_u = viewport_u / vec3.splat(width_f);
        self.pixel_delta_v = viewport_v / vec3.splat(height_f);

        // Walk from the camera center out to the viewport's upper-left corner
        // (forward by focus_dist, then half the width left and half the height
        // up), then inset by half a pixel so pixel00_loc lands on the *center*
        // of the top-left pixel rather than its corner.
        const viewport_upper_left = self.center - self.w * vec3.splat(self.focus_dist) -
            viewport_u / vec3.splat(2.0) - viewport_v / vec3.splat(2.0);
        self.pixel00_loc = viewport_upper_left + (self.pixel_delta_u + self.pixel_delta_v) * vec3.splat(0.5);

        const defocus_radius = self.focus_dist * std.math.tan(util.degreesToRadians(self.defocus_angle / 2));
        self.defocus_disk_u = self.u * vec3.splat(defocus_radius);
        self.defocus_disk_v = self.v * vec3.splat(defocus_radius);
    }

    // Shared state for one parallel render: every worker pulls the next
    // unclaimed scanline off `next_row` and writes only into that row's slice of
    // `pixels`, so no two workers ever touch the same pixel.
    const Job = struct {
        cam: *const Camera,
        world: hittable_list.HittableList,
        pixels: []vec3.Color,
        next_row: std.atomic.Value(u32),
        rows_left: std.atomic.Value(u32),
    };

    // Renders the whole image to `stdout` in PPM format, writing progress to
    // `stderr`. For each pixel, fires `samples_per_pixel` rays through slightly
    // jittered points within that pixel and averages the resulting colors —
    // this random supersampling is what smooths out jagged edges (antialiasing)
    // instead of every pixel being a single hard sample.
    //
    // Scanlines are rendered in parallel (see renderRows) into a full-image
    // buffer, then written out in order once everything is done — PPM is
    // positional, so the pixels can't be streamed out of order.
    pub fn render(
        self: *Camera,
        io: std.Io,
        gpa: std.mem.Allocator,
        world: hittable_list.HittableList,
        stdout: *std.Io.Writer,
        stderr: *std.Io.Writer,
    ) !void {
        self.initialize();

        const pixels = try gpa.alloc(vec3.Color, self.image_width * self.image_height);
        defer gpa.free(pixels);

        var job: Job = .{
            .cam = self,
            .world = world,
            .pixels = pixels,
            .next_row = .init(0),
            .rows_left = .init(self.image_height),
        };

        // One worker per core, minus one because this thread renders rows too —
        // and it's the only one that touches `stderr`, so the progress log needs
        // no synchronization. `concurrent` (not `async`) because these are
        // CPU-bound: a task that doesn't get its own thread is worthless here.
        const cpus = std.Thread.getCpuCount() catch 1;
        var group: std.Io.Group = .init;
        defer group.cancel(io); // no-op after a successful await; cleans up on error
        for (1..@min(cpus, self.image_height)) |_| {
            group.concurrent(io, renderRows, .{ &job, null }) catch break;
        }
        renderRows(&job, stderr);
        try group.await(io);

        try stdout.print("P3\n{} {}\n255\n", .{ self.image_width, self.image_height });
        for (pixels) |c| try color.writeColor(stdout, c);
        try stdout.flush();
        try stderr.print("\rDone.                    \n", .{});
        try stderr.flush();
    }

    // Worker loop: claim scanlines until there are none left. `stderr` is
    // non-null for exactly one worker, which reports progress for all of them.
    fn renderRows(job: *Job, stderr: ?*std.Io.Writer) void {
        const self = job.cam;
        while (true) {
            const j = job.next_row.fetchAdd(1, .monotonic);
            if (j >= self.image_height) return;

            // Seed from the row index so a scanline renders identically no
            // matter which worker claims it (see util.seedRandom). The odd
            // constant is the golden-ratio mixer, to spread consecutive row
            // indices across distant parts of the seed space.
            util.seedRandom(0x9E3779B97F4A7C15 *% (@as(u64, j) + 1));

            const row = job.pixels[j * self.image_width ..][0..self.image_width];
            for (row, 0..) |*pixel, i| {
                var pixel_color = vec3.zero;
                for (0..self.samples_per_pixel) |_| {
                    pixel_color += rayColor(self.getRay(i, j), self.max_depth, job.world);
                }
                // Average the samples (multiply by 1/N) rather than sum them,
                // so the final brightness doesn't scale with sample count.
                pixel.* = pixel_color * vec3.splat(self.pixel_samples_scale);
            }

            const left = job.rows_left.fetchSub(1, .monotonic) - 1;
            if (stderr) |w| {
                w.print("\rScanlines remaining: {} ", .{left}) catch {};
                w.flush() catch {};
            }
        }
    }

    // Decides the color a single ray sees: the color of whatever it hits, or a
    // sky-blue-to-white gradient background if it hits nothing. `depth` counts
    // down remaining bounces; at 0 we stop recursing and return black, which
    // bounds the recursion at the cost of biasing deep paths dark.
    fn rayColor(r_in: ray.Ray, depth: u32, world: hittable_list.HittableList) vec3.Color {
        if (depth == 0) return vec3.zero;

        // min = 0.001 (not 0) to avoid "shadow acne": floating-point error in
        // rec.p can otherwise make the bounced ray re-hit the same surface at
        // t ~ 0, which without a depth cap recurses forever.
        if (world.hit(r_in, .{ .min = 0.001, .max = std.math.inf(f64) })) |rec| {
            const s = rec.mat.scatter(r_in, rec) orelse return vec3.zero;
            return s.attenuation * rayColor(s.ray, depth - 1, world);
        }

        // Background gradient: blend white -> light blue based on the ray's
        // y-direction, so straight-down rays are white and straight-up rays are
        // blue (`a` in [0,1] is a linear interpolation factor, i.e. a "lerp":
        // unit_direction[1] is in [-1, 1] so +1 then *0.5 remaps it to [0, 1]).
        const unit_direction = vec3.unitVector(r_in.direction);
        const a = 0.5 * (unit_direction[1] + 1.0);
        return vec3.splat(1.0 - a) + vec3.init(0.5, 0.7, 1.0) * vec3.splat(a);
    }

    // Builds a camera ray through pixel (i, j), offset by a random sub-pixel
    // jitter so repeated calls for the same pixel sample slightly different
    // points within it (see render()'s sample loop).
    fn getRay(self: Camera, i: usize, j: usize) ray.Ray {
        const offset = sampleSquare();
        const pixel_sample = self.pixel00_loc +
            self.pixel_delta_u * vec3.splat(@as(f64, @floatFromInt(i)) + offset[0]) +
            self.pixel_delta_v * vec3.splat(@as(f64, @floatFromInt(j)) + offset[1]);
        const origin = if (self.defocus_angle > 0) self.defocusDiskSample() else self.center;
        return .{ .origin = origin, .direction = pixel_sample - origin };
    }

    // Picks a random origin point on the camera's defocus disk (a circle of
    // radius `defocus_radius` around `center`, in the camera's own u/v plane)
    // instead of always firing from the exact camera center — this is what
    // produces depth-of-field blur for anything not at focus_dist.
    fn defocusDiskSample(self: Camera) vec3.Point {
        const p = vec3.randomInUnitDisk();
        return self.center + self.defocus_disk_u * vec3.splat(p[0]) + self.defocus_disk_v * vec3.splat(p[1]);
    }

    // A random offset in [-0.5, 0.5] x [-0.5, 0.5], i.e. a random point within
    // a unit square centered on the origin. Added to a pixel's own (i, j)
    // coordinates in getRay, this is what lets the sample land anywhere within
    // the pixel's footprint rather than always dead center.
    fn sampleSquare() vec3.Vec3 {
        return vec3.init(util.randomDouble() - 0.5, util.randomDouble() - 0.5, 0);
    }
};

test "initialize derives a sane viewport from the public config" {
    var cam = Camera{ .aspect_ratio = 16.0 / 9.0, .image_width = 1600, .samples_per_pixel = 4 };
    cam.initialize();

    try std.testing.expectEqual(@as(u32, 900), cam.image_height);
    try std.testing.expectEqual(@as(f64, 0.25), cam.pixel_samples_scale);
    // u/v/w are an orthonormal basis.
    for ([_]vec3.Vec3{ cam.u, cam.v, cam.w }) |b| {
        try std.testing.expectApproxEqAbs(@as(f64, 1), vec3.length(b), 1e-12);
    }
    try std.testing.expectApproxEqAbs(@as(f64, 0), vec3.dot(cam.u, cam.v), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0), vec3.dot(cam.v, cam.w), 1e-12);
    // Row 0 is the top of the image, so pixel_delta_v must point down (-y).
    try std.testing.expect(cam.pixel_delta_v[1] < 0);
}

test "a degenerate aspect_ratio yields a 1-pixel-tall image instead of tripping @intFromFloat" {
    for ([_]f64{ 0, -4, std.math.nan(f64), 1e-300 }) |bad| {
        var cam = Camera{ .aspect_ratio = bad, .image_width = 100 };
        cam.initialize();
        try std.testing.expect(cam.image_height >= 1);
    }
}

test "getRay jitter stays inside the pixel it belongs to" {
    var cam = Camera{ .aspect_ratio = 1, .image_width = 100 };
    cam.initialize();

    // Every sample for pixel (0,0) must land within half a pixel step of that
    // pixel's center, in both directions.
    for (0..1000) |_| {
        const r = cam.getRay(0, 0);
        const target = r.origin + r.direction;
        const off = target - cam.pixel00_loc;
        try std.testing.expect(@abs(vec3.dot(off, vec3.unitVector(cam.pixel_delta_u))) <=
            vec3.length(cam.pixel_delta_u) * 0.5 + 1e-12);
        try std.testing.expect(@abs(vec3.dot(off, vec3.unitVector(cam.pixel_delta_v))) <=
            vec3.length(cam.pixel_delta_v) * 0.5 + 1e-12);
    }
}

test "rayColor returns the sky gradient when nothing is hit" {
    var world = hittable_list.HittableList.init(std.testing.allocator);
    defer world.deinit();

    const up = Camera.rayColor(.{ .origin = vec3.zero, .direction = vec3.init(0, 1, 0) }, 10, world);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), up[0], 1e-12); // full blue end
    const down = Camera.rayColor(.{ .origin = vec3.zero, .direction = vec3.init(0, -1, 0) }, 10, world);
    try std.testing.expectEqual(vec3.splat(1), down); // full white end

    // Out of bounces contributes no light at all.
    try std.testing.expectEqual(vec3.zero, Camera.rayColor(.{ .origin = vec3.zero, .direction = vec3.init(0, 1, 0) }, 0, world));
}
