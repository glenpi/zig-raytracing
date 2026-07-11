const std = @import("std");
const ray = @import("ray.zig");
const hittable = @import("hittable.zig");
const color = @import("color.zig");
const vec3 = @import("vec3.zig");
const util = @import("util.zig");

// Matte/diffuse surface. Scatters the incoming ray in a random direction
// biased toward the surface normal (Lambertian reflectance), and tints it
// by `albedo` (the fraction of light reflected per color channel).
pub const Lambertian = struct {
    albedo: color.Color,

    pub fn scatter(self: Lambertian, _: ray.Ray, rec: hittable.HitRecord, attenuation: *color.Color, scattered: *ray.Ray) bool {
        // normal + a random unit vector gives a cosine-weighted random
        // direction in the hemisphere around the normal — this is what
        // makes diffuse surfaces look "matte" rather than mirror-like.
        var scatter_direction = rec.normal.add(vec3.Vec3.randomUnitVector());

        // If the random vector happens to exactly cancel the normal, fall
        // back to the normal itself so we never scatter a zero-length ray.
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

// Reflective surface. `fuzz` (0 = perfect mirror, higher = blurrier
// reflection) jitters the reflected ray by a random offset scaled by fuzz.
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
        // If fuzz pushed the reflected ray below the surface, treat it as
        // absorbed (return false) rather than letting it bounce inward.
        return scattered.direction.dot(rec.normal) > 0;
    }
};

// Transparent surface (glass, water, etc.) that refracts light according to
// Snell's law, with Schlick's approximation used to decide when to reflect
// instead of refract (real glass partially reflects at glancing angles).
pub const Dielectric = struct {
    refraction_index: f64,

    pub fn scatter(self: Dielectric, r_in: ray.Ray, rec: hittable.HitRecord, attenuation: *color.Color, scattered: *ray.Ray) bool {
        // Glass doesn't absorb any color itself.
        attenuation.* = color.Color{
            .x = 1,
            .y = 1,
            .z = 1,
        };
        // Light bends more going from a denser to a less dense medium, so
        // the ratio flips depending on whether we're entering or exiting
        // the surface (front_face tells us which).
        var ri = self.refraction_index;
        if (rec.front_face) {
            ri = 1 / self.refraction_index;
        }
        const unit_direction = vec3.Vec3.unitVector(r_in.direction);
        const cos_theta = @min(unit_direction.neg().dot(rec.normal), 1.0);
        const sin_theta = @sqrt(1 - cos_theta * cos_theta);

        // Snell's law has no solution past the critical angle (total
        // internal reflection) — when that happens, or when Schlick's
        // approximation says reflection is more likely at this angle,
        // reflect instead of refract.
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

    // Schlick's approximation: cheap estimate of the Fresnel reflectance
    // (how much light reflects vs. refracts) as a function of viewing angle.
    fn reflectance(cosine: f64, refraction_index: f64) f64 {
        var r0 = (1 - refraction_index) / (1 + refraction_index);
        r0 = r0 * r0;
        return r0 + (1 - r0) * std.math.pow(f64, 1 - cosine, 5);
    }
};

// Zig has no classes/inheritance, so "any surface a ray can scatter off of"
// is modeled as a tagged union of the concrete material types instead of an
// interface — see the matching comment on `Hittable` in hittable.zig for
// the same pattern applied to shapes.
pub const Material = union(enum) {
    lambertian: Lambertian,
    metal: Metal,
    dielectric: Dielectric,

    pub fn scatter(self: Material, r_in: ray.Ray, rec: hittable.HitRecord, attenuation: *color.Color, scattered: *ray.Ray) bool {
        return switch (self) {
            inline else => |m| m.scatter(r_in, rec, attenuation, scattered),
        };
    }
};
