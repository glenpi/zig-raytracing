const ray = @import("ray.zig");
const hittable = @import("hittable.zig");
const color = @import("color.zig");
const vec3 = @import("vec3.zig");

pub const Lambertian = struct {
    albedo: color.Color,
    pub fn scatter(self: Lambertian, _: ray.Ray, rec: hittable.HitRecord, attenuation: *color.Color, scattered: *ray.Ray) bool {
        var scatter_direction = rec.normal.add(vec3.Vec3.randomUnitVector());

        if (scatter_direction.nearZero()) {
            scatter_direction = rec.normal;
        }

        scattered.* = ray.Ray{
            .origin = rec.p,
            .direction = scatter_direction,
        };
        attenuation.* = self.albedo;
        return true;
    }
};
