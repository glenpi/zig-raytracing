const std = @import("std");
const h = @import("hittable.zig");
const hl = @import("hittable_list.zig");
const r = @import("ray.zig");
const c = @import("color.zig");
const interval = @import("interval.zig");
const vec3 = @import("vec3.zig");
const rtw = @import("rtweekend.zig");
const util = @import("util.zig");

const Ray = r.Ray;
const Hittable = h.Hittable;
const HittableList = hl.HittableList;
const Color = c.Color;
const HitRecord = h.HitRecord;
const Interval = interval.Interval;
const Point = vec3.Point;
const Vec3 = vec3.Vec3;

pub const Camera = struct {
    // --- Public configuration, set by the caller (see main.zig) before render() ---
    aspect_ratio: f64 = 1.0,
    image_width: u32 = 100,
    samples_per_pixel: u32 = 10, // rays per pixel, for antialiasing (see getRay)
    max_depth: u32 = 10, // max ray bounces; caps recursion in rayColor()
    pixel_samples_scale: f64 = 0, // = 1/samples_per_pixel, precomputed to average samples cheaply

    // --- Derived state, computed by initialize() from the config above ---
    image_height: u32 = 0,
    center: Point = Point{}, // camera/eye position, at the origin
    pixel00_loc: Point = Point{}, // world-space location of pixel (0,0)'s center
    pixel_delta_u: Vec3 = Vec3{}, // world-space offset from one pixel to the next, horizontally
    pixel_delta_v: Vec3 = Vec3{}, // world-space offset from one pixel to the next, vertically

    // Sets up the virtual "viewport": a rectangle one focal_length in front
    // of the camera, sized in world units (viewport_height/width), that maps
    // 1:1 onto the image's pixel grid. Everything here is just figuring out,
    // for each pixel index (i, j), what 3D point it corresponds to on that
    // rectangle — that point becomes a ray's target in getRay().
    fn initialize(self: *Camera) void {
        self.image_height = @intFromFloat(@as(f64, @floatFromInt(self.image_width)) / self.aspect_ratio);
        self.image_height = @max(1, self.image_height); // guard against rounding image_height to 0

        self.pixel_samples_scale = 1.0 / @as(f64, @floatFromInt(self.samples_per_pixel));

        self.center = Point{};

        const focal_length = 1.0;
        const viewport_height = 2.0;
        // Recompute width from the *actual* image_height (which was rounded
        // to an integer) rather than reusing aspect_ratio directly, so the
        // viewport's aspect ratio matches the image's aspect ratio exactly.
        const viewport_width = viewport_height * (@as(f64, @floatFromInt(self.image_width)) / @as(f64, @floatFromInt(self.image_height)));

        // Vectors across the horizontal and down the vertical viewport edges.
        // viewport_v points -y (down) because image row 0 is the top of the
        // image but +y is "up" in world space.
        const viewport_u = Vec3{ .x = viewport_width, .y = 0, .z = 0 };
        const viewport_v = Vec3{ .x = 0, .y = -viewport_height, .z = 0 };

        // Per-pixel step vectors: dividing the full viewport edge by the
        // pixel count gives the world-space distance between adjacent
        // pixel centers.
        self.pixel_delta_u = viewport_u.divide(@as(f64, @floatFromInt(self.image_width)));
        self.pixel_delta_v = viewport_v.divide(@as(f64, @floatFromInt(self.image_height)));

        // Walk from the camera center out to the viewport's upper-left
        // corner (forward by focal_length, then half the width left and
        // half the height up), then inset by half a pixel so pixel00_loc
        // lands on the *center* of the top-left pixel rather than its corner.
        const viewport_upper_left = self.center.subtract(Vec3{ .x = 0, .y = 0, .z = focal_length }).subtract(viewport_u.divide(2.0)).subtract(viewport_v.divide(2.0));
        self.pixel00_loc = viewport_upper_left.add((self.pixel_delta_u.add(self.pixel_delta_v)).multiply(0.5));
    }

    // Renders the whole image to `stdout` in PPM format, writing progress
    // to `stderr`. For each pixel, fires `samples_per_pixel` rays through
    // slightly jittered points within that pixel and averages the resulting
    // colors — this random supersampling is what smooths out jagged edges
    // (antialiasing) instead of every pixel being a single hard sample.
    pub fn render(self: *Camera, world: HittableList, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !void {
        self.initialize();

        try stdout.print("P3\n{} {}\n255\n", .{ self.image_width, self.image_height });

        for (0..self.image_height) |j| {
            try stderr.print("\rScanlines remaining: {} ", .{self.image_height - j});
            try stderr.flush();
            for (0..self.image_width) |i| {
                var pixel_color = Color{
                    .x = 0,
                    .y = 0,
                    .z = 0,
                };
                for (0..self.samples_per_pixel) |_| {
                    const ray_sample = getRay(self, @intCast(i), @intCast(j));
                    pixel_color = pixel_color.add(rayColor(ray_sample, self.max_depth, world));
                }
                // Average the samples (multiply by 1/N) rather than sum them,
                // so the final brightness doesn't scale with sample count.
                try c.writeColor(stdout, pixel_color.multiply(self.pixel_samples_scale));
            }
        }
        try stdout.flush();
        try stderr.print("\rDone.                    \n", .{});
        try stderr.flush();
    }

    // Decides the color a single ray sees: the color of whatever it hits,
    // or a sky-blue-to-white gradient background if it hits nothing.
    // `depth` counts down remaining bounces; once it hits 0 we stop
    // recursing and contribute no more light, which both bounds the
    // recursion and models energy loss from repeated bounces.
    fn rayColor(ray: Ray, depth: u32, world: HittableList) Color {
        if (depth <= 0) {
            return Color{ .x = 0, .y = 0, .z = 0 };
        }

        var rec: HitRecord = undefined;
        // min = 0.001 (not 0) to avoid "shadow acne": floating-point error
        // in rec.p can otherwise make the bounced ray re-hit the same
        // surface at t ~ 0, which without a depth cap recurses forever.
        if (world.hit(ray, Interval{ .min = 0.001, .max = rtw.infinity }, &rec)) {
            // Debug/placeholder shading: map each normal component from
            // [-1, 1] to a color component in [0, 1] so surface normals are
            // visible as colors (no real lighting model yet).
            const direction = rec.normal.add(Vec3.randomUnitVector());
            return rayColor(Ray{
                .origin = rec.p,
                .direction = direction,
            }, depth - 1, world).multiply(0.1);
        }
        // Background gradient: blend white -> light blue based on the ray's
        // y-direction, so straight-down rays are white and straight-up rays
        // are blue (`a` in [0,1] is a linear interpolation factor, i.e a
        // "lerp": unit_direction.y is in [-1, 1] so +1 then *0.5 remaps it
        // to [0, 1]).
        const unit_direction = ray.direction.unitVector();
        const a = 0.5 * (unit_direction.y + 1.0);
        return (Color{ .x = 1.0, .y = 1.0, .z = 1.0 }).multiply(1.0 - a).add((Color{ .x = 0.5, .y = 0.7, .z = 1.0 }).multiply(a));
    }

    // Builds a camera ray through pixel (i, j), offset by a random
    // sub-pixel jitter so repeated calls for the same pixel sample slightly
    // different points within it (see render()'s sample loop).
    fn getRay(self: *Camera, i: u32, j: u32) Ray {
        const offset = sampleSquare();
        const pixel_sample = self.pixel00_loc.add(self.pixel_delta_u.multiply(i + offset.x)).add(self.pixel_delta_v.multiply(j + offset.y));
        const ray_origin = self.center;
        const ray_direction = pixel_sample.subtract(ray_origin);
        return Ray{
            .origin = ray_origin,
            .direction = ray_direction,
        };
    }

    // A random offset in [-0.5, 0.5] x [-0.5, 0.5], i.e. a random point
    // within a unit square centered on the origin. Added to a pixel's own
    // (i, j) coordinates in getRay, this is what lets the sample land
    // anywhere within the pixel's footprint rather than always dead center.
    fn sampleSquare() Vec3 {
        return Vec3{
            .x = util.randomDouble() - 0.5,
            .y = util.randomDouble() - 0.5,
            .z = 0,
        };
    }
};
