const std = @import("std");
const rtweekend = @import("rtweekend.zig");
const camera = @import("camera.zig");
const lambertian = @import("lambertian.zig");
const material = @import("material.zig");
const metal = @import("metal.zig");
const color = @import("color.zig");
const dielectric = @import("dielectric.zig");
const vec3 = @import("vec3.zig");

pub fn main(init: std.process.Init) !void {
    // World: a small sphere floating at z=-1 (in front of the camera, which
    // sits at the origin looking down -z), plus a much bigger sphere below
    // it that's so large its curvature reads as a flat ground plane.
    var world = rtweekend.HittableList.init(init.gpa);
    defer world.deinit();

    //const R = std.math.cos(rtweekend.pi / 4);

    const material_ground = material.Material{ .lambertian = lambertian.Lambertian{ .albedo = color.Color{
        .x = 0.5,
        .y = 0.5,
        .z = 0.5,
    } } };

    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
        .center = rtweekend.Point{ .x = 0, .y = -1000, .z = 0 },
        .radius = 1000,
        .mat = material_ground,
    } });

    //TODO

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
                var sphere_material: material.Material = undefined;
                if (choose_mat < 0.8) {
                    const albedo = color.Color.random().hadamardProduct(color.Color.random());
                    sphere_material = material.Material{ .lambertian = lambertian.Lambertian{ .albedo = albedo } };
                    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
                        .center = center,
                        .radius = 0.2,
                        .mat = sphere_material,
                    } });
                } else if (choose_mat < 0.95) {
                    const albedo = color.Color.randomWithRange(0.5, 1);
                    const fuzz = rtweekend.util.randomDouble();
                    sphere_material = material.Material{ .metal = metal.Metal{
                        .albedo = albedo,
                        .fuzz = fuzz,
                    } };
                    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
                        .center = center,
                        .radius = 0.2,
                        .mat = sphere_material,
                    } });
                } else {
                    sphere_material = material.Material{ .dielectric = dielectric.Dielectric{ .refraction_index = 1.5 } };
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

    const material1 = material.Material{ .dielectric = dielectric.Dielectric{ .refraction_index = 1.5 } };

    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
        .center = rtweekend.Point{ .x = 0, .y = 1, .z = 0 },
        .radius = 1,
        .mat = material1,
    } });

    const material2 = material.Material{ .lambertian = lambertian.Lambertian{ .albedo = color.Color{
        .x = 0.4,
        .y = 0.2,
        .z = 0.1,
    } } };

    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
        .center = rtweekend.Point{ .x = -4, .y = 1, .z = 0 },
        .radius = 1,
        .mat = material2,
    } });

    const material3 = material.Material{ .metal = metal.Metal{
        .albedo = color.Color{
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

    var cam = camera.Camera{
        .aspect_ratio = 16.0 / 9.0,
        .image_width = 1200,
        .samples_per_pixel = 500, // rays averaged per pixel for antialiasing
        .max_depth = 50,
        .vfov = 20,
        .lookfrom = vec3.Point{
            .x = 13,
            .y = 2,
            .z = 3,
        },
        .lookat = vec3.Point{
            .x = 0,
            .y = 0,
            .z = 0,
        },
        .vup = vec3.Vec3{
            .x = 0,
            .y = 1,
            .z = 0,
        },
        .defocus_angle = 0.6,
        .focus_dist = 10.0,
    };

    try cam.render(world, stdout, stderr);
}
