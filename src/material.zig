const std = @import("std");
const ray = @import("ray.zig");
const hittable = @import("hittable.zig");
const vec3 = @import("vec3.zig");
const util = @import("util.zig");

// What a surface did to an incoming ray: where it went next, and how much of
// each color channel survived the bounce. `scatter` returns null instead when
// the ray was absorbed outright.
pub const Scatter = struct {
    attenuation: vec3.Color,
    ray: ray.Ray,
};

// Matte/diffuse surface. Scatters the incoming ray in a random direction biased
// toward the surface normal (Lambertian reflectance), and tints it by `albedo`
// (the fraction of light reflected per color channel).
pub const Lambertian = struct {
    albedo: vec3.Color,

    pub fn scatter(self: Lambertian, _: ray.Ray, rec: hittable.HitRecord) ?Scatter {
        // normal + a random unit vector gives a cosine-weighted random
        // direction in the hemisphere around the normal — this is what makes
        // diffuse surfaces look "matte" rather than mirror-like.
        const direction = rec.normal + vec3.randomUnitVector();

        return .{
            .attenuation = self.albedo,
            .ray = .{
                .origin = rec.p,
                // If the random vector happened to almost exactly cancel the
                // normal, fall back to the normal itself so we never scatter a
                // zero-length ray.
                .direction = if (vec3.nearZero(direction)) rec.normal else direction,
            },
        };
    }
};

// Reflective surface. `fuzz` (0 = perfect mirror, higher = blurrier reflection)
// jitters the reflected ray by a random offset scaled by fuzz.
pub const Metal = struct {
    albedo: vec3.Color,
    // Clamped to 1 on use: beyond that the jitter dominates the reflection and
    // almost every ray is pushed below the surface and absorbed, silently
    // turning the metal black. The book enforces this in a constructor, which
    // a Zig struct literal doesn't have.
    fuzz: f64,

    pub fn scatter(self: Metal, r_in: ray.Ray, rec: hittable.HitRecord) ?Scatter {
        const reflected = vec3.unitVector(vec3.reflect(r_in.direction, rec.normal)) +
            vec3.randomUnitVector() * vec3.splat(@min(self.fuzz, 1));

        // If fuzz pushed the reflected ray below the surface, treat it as
        // absorbed rather than letting it bounce inward.
        if (vec3.dot(reflected, rec.normal) <= 0) return null;

        return .{
            .attenuation = self.albedo,
            .ray = .{ .origin = rec.p, .direction = reflected },
        };
    }
};

// Transparent surface (glass, water, etc.) that refracts light according to
// Snell's law, with Schlick's approximation used to decide when to reflect
// instead of refract (real glass partially reflects at glancing angles).
pub const Dielectric = struct {
    refraction_index: f64,

    pub fn scatter(self: Dielectric, r_in: ray.Ray, rec: hittable.HitRecord) ?Scatter {
        // Light bends more going from a denser to a less dense medium, so the
        // ratio flips depending on whether we're entering or exiting the
        // surface (front_face tells us which).
        const ri = if (rec.front_face) 1 / self.refraction_index else self.refraction_index;

        const unit_direction = vec3.unitVector(r_in.direction);
        const cos_theta = @min(vec3.dot(-unit_direction, rec.normal), 1.0);
        const sin_theta = @sqrt(1 - cos_theta * cos_theta);

        // Snell's law has no solution past the critical angle (total internal
        // reflection) — when that happens, or when Schlick's approximation says
        // reflection is more likely at this angle, reflect instead of refract.
        const cannot_refract = ri * sin_theta > 1.0;
        const direction = if (cannot_refract or reflectance(cos_theta, ri) > util.randomDouble())
            vec3.reflect(unit_direction, rec.normal)
        else
            vec3.refract(unit_direction, rec.normal, ri);

        return .{
            // Glass doesn't absorb any color itself.
            .attenuation = vec3.splat(1),
            .ray = .{ .origin = rec.p, .direction = direction },
        };
    }

    // Schlick's approximation: cheap estimate of the Fresnel reflectance (how
    // much light reflects vs. refracts) as a function of viewing angle.
    fn reflectance(cosine: f64, refraction_index: f64) f64 {
        const r0 = (1 - refraction_index) / (1 + refraction_index);
        const r0_sq = r0 * r0;
        return r0_sq + (1 - r0_sq) * std.math.pow(f64, 1 - cosine, 5);
    }
};

// Zig has no classes/inheritance, so "any surface a ray can scatter off of" is
// modeled as a tagged union of the concrete material types instead of an
// interface — see the matching comment on `Hittable` in hittable.zig for the
// same pattern applied to shapes.
pub const Material = union(enum) {
    lambertian: Lambertian,
    metal: Metal,
    dielectric: Dielectric,

    pub fn scatter(self: Material, r_in: ray.Ray, rec: hittable.HitRecord) ?Scatter {
        return switch (self) {
            inline else => |m| m.scatter(r_in, rec),
        };
    }
};

// A ray travelling straight down onto a flat, upward-facing surface at the
// origin — the simplest geometry to reason about analytically.
fn headOnHit(mat: Material) hittable.HitRecord {
    return .{
        .p = vec3.zero,
        .normal = vec3.init(0, 1, 0),
        .mat = mat,
        .t = 1,
        .front_face = true,
    };
}

const straight_down = ray.Ray{ .origin = vec3.init(0, 1, 0), .direction = vec3.init(0, -1, 0) };

test "lambertian always scatters, into the hemisphere above the surface" {
    const mat = Material{ .lambertian = .{ .albedo = vec3.init(0.1, 0.2, 0.3) } };
    for (0..1000) |_| {
        const s = mat.scatter(straight_down, headOnHit(mat)).?;
        try std.testing.expectEqual(vec3.init(0.1, 0.2, 0.3), s.attenuation);
        try std.testing.expect(!vec3.nearZero(s.ray.direction));
        // normal + a unit vector can never point below the surface.
        try std.testing.expect(s.ray.direction[1] >= 0);
    }
}

test "a mirror reflects straight back, and fuzz stays clamped to usable metal" {
    const mirror = Material{ .metal = .{ .albedo = vec3.splat(1), .fuzz = 0 } };
    const s = mirror.scatter(straight_down, headOnHit(mirror)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 1), s.ray.direction[1], 1e-12);

    // Without the @min(fuzz, 1), a large fuzz would absorb nearly every ray and
    // render the surface black. Clamped, most rays still scatter.
    const rough = Material{ .metal = .{ .albedo = vec3.splat(1), .fuzz = 50 } };
    var scattered: usize = 0;
    for (0..1000) |_| {
        if (rough.scatter(straight_down, headOnHit(rough)) != null) scattered += 1;
    }
    try std.testing.expect(scattered > 400);
}

test "dielectric always scatters and never tints" {
    const glass = Material{ .dielectric = .{ .refraction_index = 1.5 } };
    for (0..1000) |_| {
        const s = glass.scatter(straight_down, headOnHit(glass)).?;
        try std.testing.expectEqual(vec3.splat(1), s.attenuation);
    }
}

test "reflectance rises to 1 at grazing angles" {
    // Head-on (cosine 1) reflects least; grazing (cosine 0) reflects fully.
    try std.testing.expectApproxEqAbs(@as(f64, 0.04), Dielectric.reflectance(1, 1.5), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1), Dielectric.reflectance(0, 1.5), 1e-12);
}
