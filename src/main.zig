const std = @import("std");
const Camera = @import("camera.zig").Camera;
const HittableList = @import("hittable_list.zig").HittableList;
const Material = @import("material.zig").Material;
const util = @import("util.zig");
const vec3 = @import("vec3.zig");

// Entry point: builds the scene (a `HittableList` of spheres) and a `Camera`,
// then renders the scene to a PPM image on stdout.
pub fn main(init: std.process.Init) !void {
    var world = try buildScene(init.gpa);
    defer world.deinit();

    // Buffered writers for the image (stdout, PPM pixel data) and progress log
    // (stderr, so it doesn't get mixed into the redirected image output when
    // running e.g. `zig build run > image.ppm`).
    var buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buf);
    var err_buf: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &err_buf);

    // Wide-angle view from high up and to the side, with a shallow depth of
    // field (small defocus_angle, focused at focus_dist = 10) so only objects
    // near the origin are sharp — the small spheres near the edges of the frame
    // blur slightly, like a real camera's aperture.
    var cam = Camera{
        .aspect_ratio = 16.0 / 9.0,
        .image_width = 1200,
        .samples_per_pixel = 500, // rays averaged per pixel for antialiasing
        .max_depth = 50,
        .vfov = 20,
        .lookfrom = vec3.init(13, 2, 3),
        .lookat = vec3.zero,
        .vup = vec3.init(0, 1, 0),
        .defocus_angle = 0.6,
        .focus_dist = 10.0,
    };

    try cam.render(init.io, init.gpa, world, &stdout_writer.interface, &stderr_writer.interface);
}

// The book's "final render" scene: a huge sphere for the ground, a randomly
// generated field of small spheres (mostly matte, some metal, a few glass)
// scattered around the origin, plus three large "feature" spheres — one of each
// material — placed by hand so they're always in frame.
fn buildScene(allocator: std.mem.Allocator) !HittableList {
    var world = HittableList.init(allocator);
    errdefer world.deinit();

    try world.add(.{ .sphere = .{
        .center = vec3.init(0, -1000, 0),
        .radius = 1000,
        .mat = .{ .lambertian = .{ .albedo = vec3.splat(0.5) } },
    } });

    // Random small-sphere field: a 22x22 grid of grid points (a, b) in
    // [-11, 11), each jittered within its cell so the spheres don't line up in
    // an obvious grid. Materials are picked by rolling a die: 80% matte, 15%
    // metal, 5% glass. Any sphere that would overlap the big glass sphere at
    // (4, 0.2, 0) is skipped so it doesn't collide with `material3` below.
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
                .{ .lambertian = .{ .albedo = vec3.random() * vec3.random() } }
            else if (choose_mat < 0.95)
                .{ .metal = .{ .albedo = vec3.randomWithRange(0.5, 1), .fuzz = util.randomDouble() } }
            else
                .{ .dielectric = .{ .refraction_index = 1.5 } };

            try world.add(.{ .sphere = .{ .center = center, .radius = 0.2, .mat = mat } });
        }
    }

    // The three large feature spheres: glass, matte, and metal.
    try world.add(.{ .sphere = .{
        .center = vec3.init(0, 1, 0),
        .radius = 1,
        .mat = .{ .dielectric = .{ .refraction_index = 1.5 } },
    } });
    try world.add(.{ .sphere = .{
        .center = vec3.init(-4, 1, 0),
        .radius = 1,
        .mat = .{ .lambertian = .{ .albedo = vec3.init(0.4, 0.2, 0.1) } },
    } });
    try world.add(.{ .sphere = .{
        .center = vec3.init(4, 1, 0),
        .radius = 1,
        .mat = .{ .metal = .{ .albedo = vec3.init(0.7, 0.6, 0.5), .fuzz = 0 } },
    } });

    return world;
}

test "the scene builds and leaves no spheres overlapping the feature sphere" {
    var world = try buildScene(std.testing.allocator);
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
