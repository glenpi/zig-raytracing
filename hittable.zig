const ray = @import("ray.zig");
const vec3 = @import("vec3.zig");
const sphere = @import("sphere.zig");
const interval = @import("interval.zig");
const material = @import("material.zig");

// Filled in by a Hittable's hit() when a ray intersects it: where the hit
// happened (`p`), the surface normal there, the ray parameter `t` at the
// hit, and which side of the surface the ray came from.
pub const HitRecord = struct {
    p: vec3.Point,
    normal: vec3.Vec3,
    mat: material.Material,
    t: f64,
    front_face: bool,

    // `outward_normal` always points away from the object's interior (e.g.
    // for a sphere: from center to surface point), regardless of which
    // direction the ray came from. This function figures out whether the
    // ray is hitting the outside or inside of the surface (via the sign of
    // the dot product — negative means the ray and normal point toward each
    // other, i.e. the ray is hitting the front) and flips the stored normal
    // so it always faces back toward the ray. Downstream code (e.g. the
    // normal-as-color visualization in camera.zig) can then rely on
    // `normal` always opposing the incoming ray rather than having to check
    // front_face itself.
    pub fn setFaceNormal(self: *HitRecord, r_in: ray.Ray, outward_normal: vec3.Vec3) void {
        self.front_face = r_in.direction.dot(outward_normal) < 0;
        if (self.front_face) {
            self.normal = outward_normal;
        } else {
            self.normal = outward_normal.neg();
        }
    }
};

// Zig has no classes/inheritance, so "any object that can be hit by a ray"
// is modeled as a tagged union of the concrete shape types instead of an
// interface. Adding a new shape (e.g. a plane) means adding a variant here
// and a branch is generated automatically by `inline else` below — no
// vtable needed.
pub const Hittable = union(enum) {
    sphere: sphere.Sphere,

    // `inline else |h|` expands to a switch over every variant at compile
    // time, calling that variant's own `hit` method. This is Zig's
    // static-dispatch stand-in for virtual methods.
    pub fn hit(self: Hittable, r_in: ray.Ray, ray_t: interval.Interval, rec: *HitRecord) bool {
        return switch (self) {
            inline else => |h| h.hit(r_in, ray_t, rec),
        };
    }
};
