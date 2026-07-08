const std = @import("std");
const rtweekend = @import("rtweekend.zig");
const camera = @import("camera.zig");
const lambertian = @import("lambertian.zig");
const material = @import("material.zig");
const metal = @import("metal.zig");
const color = @import("color.zig");

pub fn main(init: std.process.Init) !void {
    // World: a small sphere floating at z=-1 (in front of the camera, which
    // sits at the origin looking down -z), plus a much bigger sphere below
    // it that's so large its curvature reads as a flat ground plane.
    var world = rtweekend.HittableList.init(init.gpa);
    defer world.deinit();

    const material_ground = material.Material{ .lambertian = lambertian.Lambertian{
        .albedo = color.Color{
            .x = 0.8,
            .y = 0.8,
            .z = 0,
        },
    } };
    const material_center = material.Material{ .lambertian = lambertian.Lambertian{
        .albedo = color.Color{
            .x = 0.1,
            .y = 0.2,
            .z = 0.5,
        },
    } };

    const material_left = material.Material{ .metal = metal.Metal{
        .albedo = color.Color{
            .x = 0.8,
            .y = 0.8,
            .z = 0.8,
        },
        .fuzz = 0.3,
    } };
    const material_right = material.Material{ .metal = metal.Metal{
        .albedo = color.Color{
            .x = 0.8,
            .y = 0.6,
            .z = 0.2,
        },
        .fuzz = 1.0,
    } };

    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
        .center = rtweekend.Point{ .x = 0, .y = -100.5, .z = -1 },
        .radius = 100,
        .mat = material_ground,
    } });
    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
        .center = rtweekend.Point{ .x = 0, .y = 0, .z = -1.2 },
        .radius = 0.5,
        .mat = material_center,
    } });

    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
        .center = rtweekend.Point{ .x = -1, .y = 0, .z = -1 },
        .radius = 0.5,
        .mat = material_left,
    } });
    try world.add(rtweekend.Hittable{ .sphere = rtweekend.Sphere{
        .center = rtweekend.Point{ .x = 1, .y = 0, .z = -1 },
        .radius = 0.5,
        .mat = material_right,
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
        .image_width = 400,
        .samples_per_pixel = 100, // rays averaged per pixel for antialiasing
        .max_depth = 50,
    };

    try cam.render(world, stdout, stderr);
}
