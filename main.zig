const std = @import("std");
const rtw = @import("rtweekend.zig");
const cam = @import("camera.zig");
const Point = rtw.Point;
const Hittable = rtw.Hittable;
const HittableList = rtw.HittableList;
const Sphere = rtw.Sphere;
const Camera = cam.Camera;

pub fn main(init: std.process.Init) !void {
    // World: a small sphere floating at z=-1 (in front of the camera, which
    // sits at the origin looking down -z), plus a much bigger sphere below
    // it that's so large its curvature reads as a flat ground plane.
    var world = HittableList.init(init.gpa);
    defer world.deinit();
    try world.add(Hittable{ .sphere = Sphere{
        .center = Point{ .x = 0, .y = 0, .z = -1 },
        .radius = 0.5,
    } });
    try world.add(Hittable{ .sphere = Sphere{
        .center = Point{ .x = 0, .y = -100.5, .z = -1 },
        .radius = 100,
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

    var camera = Camera{
        .aspect_ratio = 16.0 / 9.0,
        .image_width = 400,
        .samples_per_pixel = 100, // rays averaged per pixel for antialiasing
        .max_depth = 50,
    };

    try camera.render(world, stdout, stderr);
}
