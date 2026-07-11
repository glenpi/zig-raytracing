const std = @import("std");

// A "barrel" module: re-exports the types/constants from every other file
// so the rest of the codebase can `@import("rtweekend.zig")` once and get
// everything, instead of importing each small module individually. Only
// main.zig should need to reach through this barrel — every other file
// imports its direct siblings so this module stays a one-directional layer
// on top, with nothing importing it back (that's what caused the old
// interval.zig <-> rtweekend.zig cycle; see interval.zig for the fix).
pub const vec3 = @import("vec3.zig");
pub const ray = @import("ray.zig");
pub const color = @import("color.zig");
pub const hittable = @import("hittable.zig");
pub const hittable_list = @import("hittable_list.zig");
pub const interval = @import("interval.zig");
pub const material = @import("material.zig");
pub const camera = @import("camera.zig");
pub const util = @import("util.zig");

pub const Vec3 = vec3.Vec3;
pub const Point = vec3.Point;
pub const Color = vec3.Color;
pub const Ray = ray.Ray;
pub const writeColor = color.writeColor;
pub const HitRecord = hittable.HitRecord;
pub const Hittable = hittable.Hittable;
pub const Sphere = hittable.Sphere;
pub const HittableList = hittable_list.HittableList;
pub const Interval = interval.Interval;
pub const empty_interval = interval.empty;
pub const universe_interval = interval.universe;
pub const Material = material.Material;
pub const Lambertian = material.Lambertian;
pub const Metal = material.Metal;
pub const Dielectric = material.Dielectric;
pub const Camera = camera.Camera;

pub const infinity = std.math.inf(f64);
pub const pi: f64 = std.math.pi;
