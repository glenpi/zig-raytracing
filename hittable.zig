const ray = @import("ray.zig");
const vec3 = @import("vec3.zig");
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

// A sphere: the simplest shape to ray-intersect analytically, and the only
// shape this raytracer currently supports (see `Hittable` below).
pub const Sphere = struct {
    center: vec3.Point,
    radius: f64,
    mat: material.Material,

    // Ray-sphere intersection. A point P is on the sphere when
    // |P - center|^2 = radius^2. Substituting the ray's P(t) = origin + t*dir
    // gives a quadratic in t: a*t^2 - 2h*t + c = 0, where:
    //   a = dir . dir            (lengthSquared of direction)
    //   h = dir . (center - origin)   (using h = -b/2 lets the /2's cancel,
    //                                   so the quadratic formula below
    //                                   simplifies to (h +/- sqrt(h^2-ac))/a
    //                                   instead of the textbook (-b +/- ...)/2a)
    //   c = |center - origin|^2 - radius^2
    // discriminant < 0 means the line never touches the sphere at all.
    pub fn hit(self: Sphere, r_in: ray.Ray, ray_t: interval.Interval, rec: *HitRecord) bool {
        const oc = self.center.subtract(r_in.origin);
        const a = r_in.direction.lengthSquared();
        const h = r_in.direction.dot(oc);
        const c = oc.lengthSquared() - self.radius * self.radius;
        const discriminant = h * h - a * c;
        if (discriminant < 0) {
            return false;
        }
        const sqrtd = @sqrt(discriminant);

        // Try the nearer root first (smaller t = closer to the ray origin);
        // only fall back to the farther root if the near one is outside the
        // acceptable t-range (e.g. behind the camera, or farther than an
        // object we've already hit — see HittableList.hit).
        var root = (h - sqrtd) / a;
        if (!ray_t.surrounds(root)) {
            root = (h + sqrtd) / a;
            if (!ray_t.surrounds(root)) {
                return false;
            }
        }
        rec.t = root;
        rec.p = r_in.at(rec.t);
        // For a sphere, the outward normal at a surface point is just the
        // direction from the center to that point (unit length since we
        // divide by radius).
        const outward_normal = (rec.p.subtract(self.center)).divide(self.radius);
        rec.setFaceNormal(r_in, outward_normal);
        rec.mat = self.mat;
        return true;
    }
};

// Zig has no classes/inheritance, so "any object that can be hit by a ray"
// is modeled as a tagged union of the concrete shape types instead of an
// interface. Adding a new shape (e.g. a plane) means adding a variant here
// and a branch is generated automatically by `inline else` below — no
// vtable needed.
pub const Hittable = union(enum) {
    sphere: Sphere,

    // `inline else |h|` expands to a switch over every variant at compile
    // time, calling that variant's own `hit` method. This is Zig's
    // static-dispatch stand-in for virtual methods.
    pub fn hit(self: Hittable, r_in: ray.Ray, ray_t: interval.Interval, rec: *HitRecord) bool {
        return switch (self) {
            inline else => |h| h.hit(r_in, ray_t, rec),
        };
    }
};
