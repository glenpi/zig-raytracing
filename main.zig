const std = @import("std");
const rtweekend = @import("rtweekend.zig");

// Entry point: builds the scene (a `HittableList` of spheres) and a
// `Camera`, then renders the scene to a PPM image on stdout.
pub fn main(init: std.process.Init) !void {
    // World: a huge sphere for the ground, a randomly generated field of
    // small spheres (mostly matte, some metal, a few glass) scattered
    // around the origin, plus three large "feature" spheres — one of each
    // material — placed by hand so they're always in frame.
    var world = rtweekend.HittableList.init(init.gpa);
    defer world.deinit();

    const material_ground = rtweekend.Material{ .lambertian = rtweekend.Lambertian{ .albedo = rtweekend.Color{
        .x = 0.5,
        .y = 0.5,
        .z = 0.5,
    } } };

    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
        .center = rtweekend.Point{ .x = 0, .y = -1000, .z = 0 },
        .radius = 1000,
        .mat = material_ground,
    } });

    // Random small-sphere field: an 22x22 grid of grid points (a, b) in
    // [-11, 11), each jittered within its cell so the spheres don't line up
    // in an obvious grid. Materials are picked by rolling a die: 80% matte,
    // 15% metal, 5% glass. Any sphere that would overlap the big sphere at
    // (4, 0.2, 0) is skipped so it doesn't collide with `material3` below.
    var a: i32 = -11;
    while (a < 11) {
        var b: i32 = -11;
        while (b < 11) {
            const choose_mat = rtweekend.util.randomDouble();
            const center = rtweekend.Point{
                .x = a + 0.9 * rtweekend.util.randomDouble(),
                .y = 0.2,
                .z = b + 0.9 * rtweekend.util.randomDouble(),
            };
            if (center.subtract(rtweekend.Point{ .x = 4, .y = 0.2, .z = 0 }).length() > 0.9) {
                var sphere_material: rtweekend.Material = undefined;
                if (choose_mat < 0.8) {
                    // hadamardProduct of two random colors biases the
                    // result toward darker, more saturated tones than a
                    // single random color would (each channel gets
                    // multiplied down rather than left uniform-random).
                    const albedo = rtweekend.Color.random().hadamardProduct(rtweekend.Color.random());
                    sphere_material = rtweekend.Material{ .lambertian = rtweekend.Lambertian{ .albedo = albedo } };
                    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
                        .center = center,
                        .radius = 0.2,
                        .mat = sphere_material,
                    } });
                } else if (choose_mat < 0.95) {
                    const albedo = rtweekend.Color.randomWithRange(0.5, 1);
                    const fuzz = rtweekend.util.randomDouble();
                    sphere_material = rtweekend.Material{ .metal = rtweekend.Metal{
                        .albedo = albedo,
                        .fuzz = fuzz,
                    } };
                    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
                        .center = center,
                        .radius = 0.2,
                        .mat = sphere_material,
                    } });
                } else {
                    sphere_material = rtweekend.Material{ .dielectric = rtweekend.Dielectric{ .refraction_index = 1.5 } };
                    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
                        .center = center,
                        .radius = 0.2,
                        .mat = sphere_material,
                    } });
                }
            }
            b += 1;
        }
        a += 1;
    }

    // The three large feature spheres: glass, matte, and metal.
    const material1 = rtweekend.Material{ .dielectric = rtweekend.Dielectric{ .refraction_index = 1.5 } };

    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
        .center = rtweekend.Point{ .x = 0, .y = 1, .z = 0 },
        .radius = 1,
        .mat = material1,
    } });

    const material2 = rtweekend.Material{ .lambertian = rtweekend.Lambertian{ .albedo = rtweekend.Color{
        .x = 0.4,
        .y = 0.2,
        .z = 0.1,
    } } };

    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
        .center = rtweekend.Point{ .x = -4, .y = 1, .z = 0 },
        .radius = 1,
        .mat = material2,
    } });

    const material3 = rtweekend.Material{ .metal = rtweekend.Metal{
        .albedo = rtweekend.Color{
            .x = 0.7,
            .y = 0.6,
            .z = 0.5,
        },
        .fuzz = 0.0,
    } };

    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
        .center = rtweekend.Point{ .x = 4, .y = 1, .z = 0 },
        .radius = 1,
        .mat = material3,
    } });

    // Buffered writers for the image (stdout, PPM pixel data) and progress
    // log (stderr, so it doesn't get mixed into the redirected image output
    // when running e.g. `zig build run > image.ppm`).
    var buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buf);
    const stdout = &stdout_writer.interface;
    var err_buf: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &err_buf);
    const stderr = &stderr_writer.interface;

    // Wide-angle view from high up and to the side, with a shallow depth of
    // field (small defocus_angle, focused at focus_dist = 10) so only
    // objects near the origin are sharp — the small spheres near the edges
    // of the frame blur slightly, like a real camera's aperture.
    var cam = rtweekend.Camera{
        .aspect_ratio = 16.0 / 9.0,
        .image_width = 1200,
        .samples_per_pixel = 500, // rays averaged per pixel for antialiasing
        .max_depth = 50,
        .vfov = 20,
        .lookfrom = rtweekend.Point{
            .x = 13,
            .y = 2,
            .z = 3,
        },
        .lookat = rtweekend.Point{
            .x = 0,
            .y = 0,
            .z = 0,
        },
        .vup = rtweekend.Vec3{
            .x = 0,
            .y = 1,
            .z = 0,
        },
        .defocus_angle = 0.6,
        .focus_dist = 10.0,
    };

    try cam.render(world, stdout, stderr);
}
