const ray = @import("ray.zig");
const hittable = @import("hittable.zig");
const color = @import("color.zig");
const lambertian = @import("lambertian.zig");
const metal = @import("metal.zig");

pub const Material = union(enum) {
    lambertian: lambertian.Lambertian,
    metal: metal.Metal,

    pub fn scatter(self: Material, r_in: ray.Ray, rec: hittable.HitRecord, attenuation: *color.Color, scattered: *ray.Ray) bool {
        return switch (self) {
            inline else => |m| m.scatter(r_in, rec, attenuation, scattered),
        };
    }
};
