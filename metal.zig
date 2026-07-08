const ray = @import("ray.zig");
const hittable = @import("hittable.zig");
const color = @import("color.zig");
const vec3 = @import("vec3.zig");

pub const Metal = struct {
    albedo: color.Color,
    fuzz: f64,
    pub fn scatter(self: Metal, r_in: ray.Ray, rec: hittable.HitRecord, attenuation: *color.Color, scattered: *ray.Ray) bool {
        var reflected = vec3.Vec3.reflect(r_in.direction, rec.normal);
        reflected = vec3.Vec3.unitVector(reflected).add(vec3.Vec3.randomUnitVector().multiply(self.fuzz));
        scattered.* = ray.Ray{
            .origin = rec.p,
            .direction = reflected,
        };
        attenuation.* = self.albedo;
        return scattered.direction.dot(rec.normal) > 0;
    }
};
