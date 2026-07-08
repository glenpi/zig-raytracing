const ray = @import("ray.zig");
const hittable = @import("hittable.zig");
const color = @import("color.zig");
const vec3 = @import("vec3.zig");

const Ray = ray.Ray;
const HitRecord = hittable.HitRecord;
const Color = color.Color;

pub const Metal = struct {
    albedo: Color,
    fuzz: f64,
    pub fn scatter(self: Metal, r_in: Ray, rec: HitRecord, attenuation: *Color, scattered: *Ray) bool {
        var reflected = vec3.Vec3.reflect(r_in.direction, rec.normal);
        reflected = vec3.Vec3.unitVector(reflected).add(vec3.Vec3.randomUnitVector().multiply(self.fuzz));
        scattered.* = Ray{
            .origin = rec.p,
            .direction = reflected,
        };
        attenuation.* = self.albedo;
        return scattered.direction.dot(rec.normal) > 0;
    }
};
