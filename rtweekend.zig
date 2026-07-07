const std = @import("std");

// A "barrel" module: re-exports the types/constants from every other file
// so the rest of the codebase can `@import("rtweekend.zig")` once and get
// everything, instead of importing each small module individually (main.zig
// and camera.zig both do this).
pub const vec3 = @import("vec3.zig");
pub const ray = @import("ray.zig");
pub const color = @import("color.zig");
pub const hittable = @import("hittable.zig");
pub const sphere = @import("sphere.zig");
pub const hittable_list = @import("hittable_list.zig");
pub const util = @import("util.zig");

pub const Vec3 = vec3.Vec3;
pub const Point = vec3.Point;
pub const Ray = ray.Ray;
pub const Color = color.Color;
pub const writeColor = color.writeColor;
pub const HitRecord = hittable.HitRecord;
pub const Hittable = hittable.Hittable;
pub const Sphere = sphere.Sphere;
pub const HittableList = hittable_list.HittableList;

pub const infinity = std.math.inf(f64);
pub const pi: f64 = std.math.pi;

pub const interval = @import("interval.zig");
pub const Interval = interval.Interval;
pub const empty_interval = interval.empty;
pub const universe_interval = interval.universe;

// Fixed seed (29) rather than a time-based one, so renders are
// reproducible between runs — handy while developing/debugging, at the
// cost of every run producing the exact same antialiasing jitter pattern.

pub fn degreesToRadians(degrees: f64) f64 {
    return degrees * pi / 180.0;
}
