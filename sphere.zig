const v = @import("vec3.zig");
const r = @import("ray.zig");
const interval = @import("interval.zig");
const hittable = @import("hittable.zig");
const Point = v.Point;
const HitRecord = hittable.HitRecord;
const Ray = r.Ray;
const Interval = interval.Interval;
const material = @import("material.zig");

pub const Sphere = struct {
    center: Point,
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
    pub fn hit(self: Sphere, ray: Ray, ray_t: Interval, rec: *HitRecord) bool {
        const oc = self.center.subtract(ray.origin);
        const a = ray.direction.lengthSquared();
        const h = ray.direction.dot(oc);
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
        rec.p = ray.at(rec.t);
        // For a sphere, the outward normal at a surface point is just the
        // direction from the center to that point (unit length since we
        // divide by radius).
        const outward_normal = (rec.p.subtract(self.center)).divide(self.radius);
        rec.setFaceNormal(ray, outward_normal);
        rec.mat = self.mat;
        return true;
    }
};
