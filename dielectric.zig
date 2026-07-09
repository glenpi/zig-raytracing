const color = @import("color.zig");
const hittable = @import("hittable.zig");
const vec3 = @import("vec3.zig");
const ray = @import("ray.zig");
const std = @import("std");
const util = @import("util.zig");

pub const Dielectric = struct {
    refraction_index: f64,

    pub fn scatter(self: Dielectric, r_in: ray.Ray, rec: hittable.HitRecord, attenuation: *color.Color, scattered: *ray.Ray) bool {
        attenuation.* = color.Color{
            .x = 1,
            .y = 1,
            .z = 1,
        };
        var ri = self.refraction_index;
        if (rec.front_face) {
            ri = 1 / self.refraction_index;
        }
        const unit_direction = vec3.Vec3.unitVector(r_in.direction);
        const cos_theta = @min(unit_direction.neg().dot(rec.normal), 1.0);
        const sin_theta = @sqrt(1 - cos_theta * cos_theta);

        const cannot_refract = ri * sin_theta > 1.0;
        var direction: vec3.Vec3 = undefined;

        if (cannot_refract or reflectance(cos_theta, ri) > util.randomDouble()) {
            direction = vec3.Vec3.reflect(unit_direction, rec.normal);
        } else {
            direction = vec3.Vec3.refract(unit_direction, rec.normal, ri);
        }

        scattered.* = ray.Ray{
            .origin = rec.p,
            .direction = direction,
        };
        return true;
    }

    fn reflectance(cosine: f64, refraction_index: f64) f64 {
        var r0 = (1 - refraction_index) / (1 + refraction_index);
        r0 = r0 * r0;
        return r0 + (1 - r0) * std.math.pow(f64, 1 - cosine, 5);
    }
};
