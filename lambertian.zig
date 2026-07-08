const ray = @import("ray.zig");
const hittable = @import("hittable.zig");
const color = @import("color.zig");
const vec3 = @import("vec3.zig");

const Ray = ray.Ray;
const HitRecord = hittable.HitRecord;
const Color = color.Color;

pub const Lambertian = struct {
    albedo: Color,
    pub fn scatter(self: Lambertian, _: Ray, rec: HitRecord, attenuation: *Color, scattered: *Ray) bool {
        var scatter_direction = rec.normal.add(vec3.Vec3.randomUnitVector());

        if (scatter_direction.nearZero()) {
            scatter_direction = rec.normal;
        }

        scattered.* = Ray{
            .origin = rec.p,
            .direction = scatter_direction,
        };
        attenuation.* = self.albedo;
        return true;
    }
};
