const util = @import("util.zig");
// General-purpose 3D vector. Reused as both a spatial `Point` and an RGB
// `Color` (see the aliases below) since all three are just "three f64s
// with the same math" in this raytracer.
pub const Vec3 = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,
    z: f64 = 0.0,

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z };
    }
    pub fn multiply(self: Vec3, t: f64) Vec3 {
        return .{ .x = self.x * t, .y = self.y * t, .z = self.z * t };
    }
    pub fn hadamardProduct(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.x * other.x,
            .y = self.y * other.y,
            .z = self.z * other.z,
        };
    }
    // Dot product: sum of componentwise products. Used to project one vector
    // onto another (e.g. checking whether a ray points into or out of a
    // surface in hittable.zig) and to compute squared length below.
    pub fn dot(self: Vec3, other: Vec3) f64 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }
    // Cross product: a vector perpendicular to both u and v, used to derive
    // the camera's "right" basis vector from vup and the view direction
    // (see camera.zig's initialize()).
    pub fn cross(u: Vec3, v: Vec3) Vec3 {
        return .{
            .x = u.y * v.z - u.z * v.y,
            .y = u.z * v.x - u.x * v.z,
            .z = u.x * v.y - u.y * v.x,
        };
    }

    pub fn subtract(self: Vec3, other: Vec3) Vec3 {
        return .{ .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z };
    }
    pub fn neg(self: Vec3) Vec3 {
        const zero = Vec3{};
        return zero.subtract(self);
    }
    pub fn divide(self: Vec3, d: f64) Vec3 {
        return .{ .x = self.x / d, .y = self.y / d, .z = self.z / d };
    }
    pub fn length(self: Vec3) f64 {
        return @sqrt(self.lengthSquared());
    }

    // Kept separate from length() because callers that only need to compare
    // magnitudes (or plug into the quadratic formula in hittable.zig's
    // Sphere.hit()) can skip the sqrt entirely.
    pub fn lengthSquared(self: Vec3) f64 {
        return self.x * self.x + self.y * self.y + self.z * self.z;
    }

    // Same direction, magnitude 1. Used whenever we need just the direction
    // of a vector, e.g. the background gradient in camera.zig.
    pub fn unitVector(self: Vec3) Vec3 {
        return self.divide(self.length());
    }

    // Rejection sampling: pick a random point in the [-1,1] x [-1,1] square
    // (z=0) and keep it only if it also falls inside the unit circle;
    // otherwise try again. Simpler than deriving a direct formula for a
    // uniform distribution over a disk, and fast since the square is only
    // ~27% bigger in area than the circle it contains. Used for
    // camera.zig's defocus-disk (depth-of-field) sampling.
    pub fn randomInUnitDisk() Vec3 {
        while (true) {
            const p = Vec3{
                .x = util.randomDoubleWithRange(-1, 1),
                .y = util.randomDoubleWithRange(-1, 1),
                .z = 0,
            };
            if (p.lengthSquared() < 1) {
                return p;
            }
        }
    }

    // Same rejection-sampling idea as randomInUnitDisk, but in 3D and then
    // normalized to land exactly on the unit sphere's surface, giving a
    // uniformly random direction. The lower bound 1e-160 guards against
    // dividing by (near) zero when a sampled point lands extremely close to
    // the origin, which would otherwise blow up to infinity/NaN.
    pub fn randomUnitVector() Vec3 {
        while (true) {
            const p = randomWithRange(-1, 1);
            const lensq = p.lengthSquared();
            if (1e-160 < lensq and lensq <= 1) {
                return p.divide(@sqrt(lensq));
            }
        }
    }

    pub fn randomOnHemisphere(normal: Vec3) Vec3 {
        const on_unit_sphere = randomUnitVector();
        if (on_unit_sphere.dot(normal) > 0.0) {
            return on_unit_sphere;
        } else {
            return on_unit_sphere.neg();
        }
    }

    pub fn random() Vec3 {
        return Vec3{
            .x = util.randomDouble(),
            .y = util.randomDouble(),
            .z = util.randomDouble(),
        };
    }

    pub fn randomWithRange(min: f64, max: f64) Vec3 {
        return Vec3{
            .x = util.randomDoubleWithRange(min, max),
            .y = util.randomDoubleWithRange(min, max),
            .z = util.randomDoubleWithRange(min, max),
        };
    }

    // True if every component is within a tiny epsilon of 0. Used by
    // Lambertian.scatter() (material.zig) to detect the degenerate case
    // where a random scatter direction almost exactly cancels the surface
    // normal, which would otherwise produce a zero-length ray direction.
    pub fn nearZero(self: Vec3) bool {
        const s = 1e-8;
        return (@abs(self.x) < s) and (@abs(self.y) < s) and (@abs(self.z) < s);
    }

    // Mirror reflection of v about normal n: v minus twice its projection
    // onto n. (The projection length is v.dot(n) since n is unit length.)
    pub fn reflect(v: Vec3, n: Vec3) Vec3 {
        return v.subtract(n.multiply(v.dot(n)).multiply(2));
    }

    // Snell's law, split into the refracted ray's components perpendicular
    // and parallel to the surface normal, then recombined.
    pub fn refract(uv: Vec3, n: Vec3, etai_over_etat: f64) Vec3 {
        const cos_theta = @min(uv.neg().dot(n), 1.0);
        const r_out_perp = uv.add(n.multiply(cos_theta)).multiply(etai_over_etat);
        const r_out_parallel = n.multiply(-@sqrt(@abs(1 - r_out_perp.lengthSquared())));
        return r_out_perp.add(r_out_parallel);
    }
};

// Both aliases are just `Vec3` under a different name so code reads
// naturally (a sphere has a `center: Point`, a material has an
// `albedo: Color`, a ray has a `direction: Vec3`) even though all three
// are the exact same underlying type.
pub const Point = Vec3;
pub const Color = Vec3;
