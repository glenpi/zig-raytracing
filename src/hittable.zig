const std = @import("std");
const ray = @import("ray.zig");
const vec3 = @import("vec3.zig");
const interval = @import("interval.zig");
const material = @import("material.zig");

// Describes where a ray met a surface: the hit point (`p`), the surface normal
// there, the ray parameter `t` at the hit, which material was hit, and which
// side of the surface the ray came from. Returned (wrapped in an optional) by
// every `hit()` in this file and in hittable_list.zig.
pub const HitRecord = struct {
    p: vec3.Point,
    normal: vec3.Vec3,
    mat: material.Material,
    t: f64,
    front_face: bool,

    // `outward_normal` always points away from the object's interior (e.g. for
    // a sphere: from center to surface point), regardless of which direction
    // the ray came from. This works out whether the ray hit the outside or the
    // inside of the surface (via the sign of the dot product — negative means
    // ray and normal point toward each other, i.e. the ray hit the front) and
    // flips the stored normal so it always faces back toward the ray.
    // Downstream code can then rely on `normal` always opposing the incoming
    // ray rather than having to check `front_face` itself.
    pub fn init(r_in: ray.Ray, t: f64, outward_normal: vec3.Vec3, mat: material.Material) HitRecord {
        const front_face = vec3.dot(r_in.direction, outward_normal) < 0;
        return .{
            .p = r_in.at(t),
            .normal = if (front_face) outward_normal else -outward_normal,
            .mat = mat,
            .t = t,
            .front_face = front_face,
        };
    }
};

// A sphere: the simplest shape to ray-intersect analytically, and the only
// shape this raytracer currently supports (see `Hittable` below).
pub const Sphere = struct {
    center: vec3.Point,
    radius: f64,
    mat: material.Material,

    // Ray-sphere intersection. A point P is on the sphere when
    // |P - center|^2 = radius^2. Substituting the ray's P(t) = origin + t*dir
    // gives a quadratic in t: a*t^2 - 2h*t + c = 0, where:
    //   a = dir . dir                 (lengthSquared of direction)
    //   h = dir . (center - origin)   (using h = -b/2 lets the /2's cancel, so
    //                                  the quadratic formula below simplifies
    //                                  to (h +/- sqrt(h^2-ac))/a instead of the
    //                                  textbook (-b +/- ...)/2a)
    //   c = |center - origin|^2 - radius^2
    // discriminant < 0 means the line never touches the sphere at all.
    pub fn hit(self: Sphere, r_in: ray.Ray, ray_t: interval.Interval) ?HitRecord {
        const oc = self.center - r_in.origin;
        const a = vec3.lengthSquared(r_in.direction);
        const h = vec3.dot(r_in.direction, oc);
        const c = vec3.lengthSquared(oc) - self.radius * self.radius;
        const discriminant = h * h - a * c;
        if (discriminant < 0) return null;
        const sqrtd = @sqrt(discriminant);

        // Try the nearer root first (smaller t = closer to the ray origin);
        // only fall back to the farther root if the near one is outside the
        // acceptable t-range (e.g. behind the camera, or farther than an object
        // we've already hit — see HittableList.hit).
        var root = (h - sqrtd) / a;
        if (!ray_t.surrounds(root)) {
            root = (h + sqrtd) / a;
            if (!ray_t.surrounds(root)) return null;
        }

        // For a sphere, the outward normal at a surface point is just the
        // direction from the center to that point (unit length since we divide
        // by radius).
        const p = r_in.at(root);
        const outward_normal = (p - self.center) / vec3.splat(self.radius);
        return HitRecord.init(r_in, root, outward_normal, self.mat);
    }
};

// Zig has no classes/inheritance, so "any object that can be hit by a ray" is
// modeled as a tagged union of the concrete shape types instead of an
// interface. Adding a new shape (e.g. a plane) means adding a variant here; the
// dispatch branch is generated automatically by `inline else` below — no vtable
// needed.
pub const Hittable = union(enum) {
    sphere: Sphere,

    // `inline else |h|` expands to a switch over every variant at compile time,
    // calling that variant's own `hit` method. This is Zig's static-dispatch
    // stand-in for virtual methods.
    pub fn hit(self: Hittable, r_in: ray.Ray, ray_t: interval.Interval) ?HitRecord {
        return switch (self) {
            inline else => |h| h.hit(r_in, ray_t),
        };
    }
};

const test_mat = material.Material{ .lambertian = .{ .albedo = vec3.splat(0.5) } };
const unit_sphere = Sphere{ .center = vec3.zero, .radius = 1, .mat = test_mat };
const everything = interval.Interval{ .min = 0.001, .max = std.math.inf(f64) };

test "hit records the near face of a sphere" {
    // Fired from (0,0,-5) toward +z, the first intersection is the front at z=-1.
    const r = ray.Ray{ .origin = vec3.init(0, 0, -5), .direction = vec3.init(0, 0, 1) };
    const rec = unit_sphere.hit(r, everything).?;
    try std.testing.expectApproxEqAbs(@as(f64, 4), rec.t, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -1), rec.p[2], 1e-12);
    try std.testing.expect(rec.front_face);
    // The normal faces back toward the ray, i.e. -z.
    try std.testing.expectApproxEqAbs(@as(f64, -1), rec.normal[2], 1e-12);
}

test "a ray starting inside hits the far face, with the normal flipped inward" {
    const r = ray.Ray{ .origin = vec3.zero, .direction = vec3.init(0, 0, 1) };
    const rec = unit_sphere.hit(r, everything).?;
    try std.testing.expectApproxEqAbs(@as(f64, 1), rec.t, 1e-12);
    try std.testing.expect(!rec.front_face);
    try std.testing.expectApproxEqAbs(@as(f64, -1), rec.normal[2], 1e-12);
}

test "misses and out-of-range hits return null" {
    const miss = ray.Ray{ .origin = vec3.init(0, 5, -5), .direction = vec3.init(0, 0, 1) };
    try std.testing.expectEqual(@as(?HitRecord, null), unit_sphere.hit(miss, everything));

    // Pointing away from the sphere: both roots are negative, so both fall
    // outside the t-range.
    const behind = ray.Ray{ .origin = vec3.init(0, 0, -5), .direction = vec3.init(0, 0, -1) };
    try std.testing.expectEqual(@as(?HitRecord, null), unit_sphere.hit(behind, everything));

    // A hit at t=4 is excluded by an interval that stops short of it.
    const near = ray.Ray{ .origin = vec3.init(0, 0, -5), .direction = vec3.init(0, 0, 1) };
    try std.testing.expectEqual(@as(?HitRecord, null), unit_sphere.hit(near, .{ .min = 0.001, .max = 3 }));
}

test "Hittable dispatches to the sphere" {
    const obj = Hittable{ .sphere = unit_sphere };
    const r = ray.Ray{ .origin = vec3.init(0, 0, -5), .direction = vec3.init(0, 0, 1) };
    try std.testing.expectApproxEqAbs(@as(f64, 4), obj.hit(r, everything).?.t, 1e-12);
}
