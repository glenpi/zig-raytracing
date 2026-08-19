const std = @import("std");
const Camera = @import("camera.zig").Camera;
const HittableList = @import("hittable_list.zig").HittableList;
const Material = @import("material.zig").Material;
const color = @import("color.zig");
const util = @import("util.zig");
const vec3 = @import("vec3.zig");

// Entry point: renders one of the book's 23 images, or all of them.
//
//     zig build run -Doptimize=ReleaseFast -- 23 > image_23.ppm
//     zig build run -Doptimize=ReleaseFast -- all
//
// A single image goes to stdout (progress to stderr, so a redirect gives a
// clean file); `all` writes image_1.ppm through image_23.ppm instead.
pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next(); // program name

    var err_buf: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &err_buf);
    const stderr = &stderr_writer.interface;

    const arg = args.next() orelse {
        try stderr.print("usage: raytracer <1-23|all>\n", .{});
        try stderr.flush();
        return error.MissingImageNumber;
    };

    var buf: [64 * 1024]u8 = undefined;

    if (std.mem.eql(u8, arg, "all")) {
        for (1..24) |n| {
            var name_buf: [32]u8 = undefined;
            const name = try std.fmt.bufPrint(&name_buf, "image_{d}.ppm", .{n});
            try stderr.print("{s}\n", .{name});
            try stderr.flush();

            const file = try std.Io.Dir.cwd().createFile(init.io, name, .{});
            defer file.close(init.io);
            var file_writer = file.writer(init.io, &buf);
            try renderImage(init, @intCast(n), &file_writer.interface, stderr);
        }
        return;
    }

    const n = std.fmt.parseInt(u32, arg, 10) catch return error.InvalidImageNumber;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buf);
    try renderImage(init, n, &stdout_writer.interface, stderr);
}

fn renderImage(init: std.process.Init, n: u32, out: *std.Io.Writer, stderr: *std.Io.Writer) !void {
    if (n == 1) return gradient(out);

    var s = try scene(init.gpa, n);
    defer s.world.deinit();
    try s.cam.render(init.io, init.gpa, s.world, out, stderr);
}

// Image 1: no rays at all, just a red/green ramp across the pixels, written to
// prove the PPM plumbing works.
fn gradient(out: *std.Io.Writer) !void {
    const size = 256;
    try out.print("P3\n{d} {d}\n255\n", .{ size, size });
    for (0..size) |j| {
        for (0..size) |i| {
            const c = vec3.init(
                @as(f64, @floatFromInt(i)) / (size - 1),
                @as(f64, @floatFromInt(j)) / (size - 1),
                0,
            );
            try color.writeColor(out, c, false);
        }
    }
    try out.flush();
}

const Scene = struct {
    world: HittableList,
    cam: Camera,
};

fn matte(albedo: vec3.Color) Material {
    return .{ .lambertian = .{ .albedo = albedo } };
}

fn metal(albedo: vec3.Color, fuzz: f64) Material {
    return .{ .metal = .{ .albedo = albedo, .fuzz = fuzz } };
}

fn glass(ir: f64) Material {
    return .{ .dielectric = .{ .refraction_index = ir } };
}

// The book's first, deliberately wrong dielectric: refracts every ray.
fn rawGlass(ir: f64) Material {
    return .{ .dielectric = .{ .refraction_index = ir, .always_refract = true } };
}

// The 23 images of the book, in order: the scene and camera it has arrived at
// by that point, so this switch doubles as a table of contents.
fn scene(gpa: std.mem.Allocator, n: u32) !Scene {
    return switch (n) {
        // A blue-to-white gradient depending on ray Y coordinate: no objects at
        // all, so every ray reaches the sky.
        2 => .{
            .world = HittableList.init(gpa),
            .cam = .{ .samples_per_pixel = 1, .jitter = false, .linear = true },
        },
        // A simple red sphere, then the same sphere colored by its normals.
        3 => .{
            .world = try oneSphere(gpa),
            .cam = .{ .samples_per_pixel = 1, .jitter = false, .linear = true, .shade = .flat_red },
        },
        4 => .{
            .world = try oneSphere(gpa),
            .cam = .{ .samples_per_pixel = 1, .jitter = false, .linear = true, .shade = .normals },
        },
        // With the ground: one sample per pixel, so aliased...
        5 => .{
            .world = try sphereAndGround(gpa),
            .cam = .{ .samples_per_pixel = 1, .jitter = false, .linear = true, .shade = .normals },
        },
        // ...then 100 jittered samples, which is the antialiasing.
        6 => .{
            .world = try sphereAndGround(gpa),
            .cam = .{ .linear = true, .shade = .normals },
        },
        // First diffuse render: uniform hemisphere bounces, no depth limit, and
        // no guard against a bounce re-hitting the surface it left.
        7 => .{
            .world = try sphereAndGround(gpa),
            .cam = .{ .linear = true, .shade = .hemisphere, .min_t = 0, .max_depth = 10_000 },
        },
        // The same scene with bounces capped at 50 — visually identical.
        8 => .{
            .world = try sphereAndGround(gpa),
            .cam = .{ .linear = true, .shade = .hemisphere, .min_t = 0 },
        },
        // Shadow acne gone: hits nearer than t = 0.001 are ignored.
        9 => .{
            .world = try sphereAndGround(gpa),
            .cam = .{ .linear = true, .shade = .hemisphere },
        },
        // True Lambertian reflection: cosine-weighted, not uniform.
        10 => .{
            .world = try sphereAndGround(gpa),
            .cam = .{ .linear = true, .shade = .lambertian },
        },
        // The gamut sweep at 10% reflectance: linear, so far too dark...
        11 => .{
            .world = try sphereAndGround(gpa),
            .cam = .{ .linear = true, .shade = .lambertian, .reflectance = 0.1 },
        },
        // ...then gamma-corrected. Every image from here on is gamma encoded.
        12 => .{
            .world = try sphereAndGround(gpa),
            .cam = .{ .shade = .lambertian, .reflectance = 0.1 },
        },
        // Shiny metal: real materials, polished spheres either side.
        13 => .{
            .world = try threeSpheres(gpa, metal(vec3.splat(0.8), 0), metal(vec3.init(0.8, 0.6, 0.2), 0)),
            .cam = .{},
        },
        14 => .{
            .world = try threeSpheres(gpa, metal(vec3.splat(0.8), 0.3), metal(vec3.init(0.8, 0.6, 0.2), 1.0)),
            .cam = .{},
        },
        // Glass first: two glass balls that always refract. Wrong, and the book
        // says so — it is the debugging step before Snell's law is finished.
        15 => blk: {
            var world = try threeSpheres(gpa, rawGlass(1.5), metal(vec3.init(0.8, 0.6, 0.2), 1.0));
            world.objects.items[1].sphere.mat = rawGlass(1.5);
            break :blk .{ .world = world, .cam = .{} };
        },
        // One glass sphere that always refracts, metal on the right.
        16 => .{
            .world = try threeSpheres(gpa, rawGlass(1.5), metal(vec3.init(0.8, 0.6, 0.2), 1.0)),
            .cam = .{},
        },
        // An air bubble in water: total internal reflection and Schlick's
        // approximation now decide between refracting and mirroring.
        17 => .{
            .world = try threeSpheres(gpa, glass(1.0 / 1.33), metal(vec3.init(0.8, 0.6, 0.2), 1.0)),
            .cam = .{},
        },
        // A hollow glass sphere: glass shell with an air bubble inside.
        18 => .{ .world = try hollowGlass(gpa), .cam = .{} },
        // A wide-angle view: two big spheres at 90 degrees vertical FOV.
        19 => blk: {
            const r = @cos(std.math.pi / 4.0);
            var world = HittableList.init(gpa);
            errdefer world.deinit();
            try world.add(.{ .sphere = .{ .center = vec3.init(-r, 0, -1), .radius = r, .mat = matte(vec3.init(0, 0, 1)) } });
            try world.add(.{ .sphere = .{ .center = vec3.init(r, 0, -1), .radius = r, .mat = matte(vec3.init(1, 0, 0)) } });
            break :blk .{ .world = world, .cam = .{} };
        },
        // A distant view: the camera moved off the origin.
        20 => .{
            .world = try hollowGlass(gpa),
            .cam = .{ .lookfrom = vec3.init(-2, 2, 1), .lookat = vec3.init(0, 0, -1) },
        },
        // Zooming in: same viewpoint, 20 degree field of view.
        21 => .{
            .world = try hollowGlass(gpa),
            .cam = .{ .vfov = 20, .lookfrom = vec3.init(-2, 2, 1), .lookat = vec3.init(0, 0, -1) },
        },
        // Spheres with depth-of-field: a 10 degree aperture focused at 3.4.
        22 => .{
            .world = try hollowGlass(gpa),
            .cam = .{
                .vfov = 20,
                .lookfrom = vec3.init(-2, 2, 1),
                .lookat = vec3.init(0, 0, -1),
                .defocus_angle = 10.0,
                .focus_dist = 3.4,
            },
        },
        // The final scene: a field of random spheres, three big ones, and
        // enough samples to make it quiet. This is the slow one.
        23 => .{
            .world = try finalScene(gpa),
            .cam = .{
                .image_width = 1200,
                .samples_per_pixel = 500,
                .vfov = 20,
                .lookfrom = vec3.init(13, 2, 3),
                .lookat = vec3.zero,
                // Just enough aperture to keep the big spheres off razor-sharp.
                .defocus_angle = 0.6,
                .focus_dist = 10.0,
            },
        },
        else => error.NoSuchImage,
    };
}

// The debug shadings never ask a sphere what it is made of, so the scenes
// before chapter 10 hand every sphere this placeholder.
const unused_mat = Material{ .lambertian = .{ .albedo = vec3.splat(0.5) } };

fn oneSphere(gpa: std.mem.Allocator) !HittableList {
    var world = HittableList.init(gpa);
    errdefer world.deinit();
    try world.add(.{ .sphere = .{ .center = vec3.init(0, 0, -1), .radius = 0.5, .mat = unused_mat } });
    return world;
}

// The two-sphere scene behind images 5 to 12.
fn sphereAndGround(gpa: std.mem.Allocator) !HittableList {
    var world = try oneSphere(gpa);
    errdefer world.deinit();
    try world.add(.{ .sphere = .{ .center = vec3.init(0, -100.5, -1), .radius = 100, .mat = unused_mat } });
    return world;
}

// The materials scene: yellow ground, a blue matte sphere in the middle, and
// whatever the chapter is demonstrating on either side.
fn threeSpheres(gpa: std.mem.Allocator, left: Material, right: Material) !HittableList {
    var world = HittableList.init(gpa);
    errdefer world.deinit();
    try world.add(.{ .sphere = .{ .center = vec3.init(0, -100.5, -1), .radius = 100, .mat = matte(vec3.init(0.8, 0.8, 0.0)) } });
    try world.add(.{ .sphere = .{ .center = vec3.init(0, 0, -1.2), .radius = 0.5, .mat = matte(vec3.init(0.1, 0.2, 0.5)) } });
    try world.add(.{ .sphere = .{ .center = vec3.init(-1, 0, -1), .radius = 0.5, .mat = left } });
    try world.add(.{ .sphere = .{ .center = vec3.init(1, 0, -1), .radius = 0.5, .mat = right } });
    return world;
}

// Adds the air bubble inside the left sphere. The inner sphere carries the
// inverse refractive index and a smaller radius, so the pair reads as a glass
// shell rather than a solid ball.
fn hollowGlass(gpa: std.mem.Allocator) !HittableList {
    var world = try threeSpheres(gpa, glass(1.5), metal(vec3.init(0.8, 0.6, 0.2), 1.0));
    errdefer world.deinit();
    try world.add(.{ .sphere = .{ .center = vec3.init(-1, 0, -1), .radius = 0.4, .mat = glass(1.0 / 1.5) } });
    return world;
}

// The book's "final render" scene: a huge sphere for the ground, a randomly
// generated field of small spheres (mostly matte, some metal, a few glass)
// scattered around the origin, plus three large "feature" spheres — one of each
// material — placed by hand so they're always in frame.
fn finalScene(gpa: std.mem.Allocator) !HittableList {
    var world = HittableList.init(gpa);
    errdefer world.deinit();

    try world.add(.{ .sphere = .{
        .center = vec3.init(0, -1000, 0),
        .radius = 1000,
        .mat = matte(vec3.splat(0.5)),
    } });

    // Random small-sphere field: a 22x22 grid of grid points (a, b) in
    // [-11, 11), each jittered within its cell so the spheres don't line up in
    // an obvious grid. Materials are picked by rolling a die: 80% matte, 15%
    // metal, 5% glass. Any sphere that would overlap the big glass sphere at
    // (4, 0.2, 0) is skipped so it doesn't collide with the feature sphere.
    for (0..22) |ai| {
        for (0..22) |bi| {
            const a: f64 = @as(f64, @floatFromInt(ai)) - 11;
            const b: f64 = @as(f64, @floatFromInt(bi)) - 11;

            const choose_mat = util.randomDouble();
            const center = vec3.init(a + 0.9 * util.randomDouble(), 0.2, b + 0.9 * util.randomDouble());
            if (vec3.length(center - vec3.init(4, 0.2, 0)) <= 0.9) continue;

            const mat: Material = if (choose_mat < 0.8)
                // Multiplying two random colors biases the result toward
                // darker, more saturated tones than a single random color
                // would (each channel gets multiplied down rather than left
                // uniform-random).
                matte(vec3.random() * vec3.random())
            else if (choose_mat < 0.95)
                metal(vec3.randomWithRange(0.5, 1), util.randomDouble())
            else
                glass(1.5);

            try world.add(.{ .sphere = .{ .center = center, .radius = 0.2, .mat = mat } });
        }
    }

    // The three large feature spheres: glass, matte, and metal.
    try world.add(.{ .sphere = .{ .center = vec3.init(0, 1, 0), .radius = 1, .mat = glass(1.5) } });
    try world.add(.{ .sphere = .{ .center = vec3.init(-4, 1, 0), .radius = 1, .mat = matte(vec3.init(0.4, 0.2, 0.1)) } });
    try world.add(.{ .sphere = .{ .center = vec3.init(4, 1, 0), .radius = 1, .mat = metal(vec3.init(0.7, 0.6, 0.5), 0) } });

    return world;
}

test "the final scene builds and leaves no spheres overlapping the feature sphere" {
    var world = try finalScene(std.testing.allocator);
    defer world.deinit();

    // 1 ground + 3 feature spheres, plus however many of the 484 grid cells
    // survived the overlap check.
    try std.testing.expect(world.objects.items.len > 400);

    for (world.objects.items) |obj| {
        const s = obj.sphere;
        if (s.radius != 0.2) continue; // ground and feature spheres are bigger
        try std.testing.expect(vec3.length(s.center - vec3.init(4, 0.2, 0)) > 0.9);
    }
}

test "every image the book has is buildable, and nothing else is" {
    for (2..24) |n| {
        var s = try scene(std.testing.allocator, @intCast(n));
        s.world.deinit();
    }
    try std.testing.expectError(error.NoSuchImage, scene(std.testing.allocator, 24));
}

test {
    // Pull in the tests from every module this binary is built from.
    _ = @import("camera.zig");
    _ = @import("color.zig");
    _ = @import("hittable.zig");
    _ = @import("hittable_list.zig");
    _ = @import("interval.zig");
    _ = @import("material.zig");
    _ = @import("ray.zig");
    _ = @import("util.zig");
    _ = @import("vec3.zig");
}
