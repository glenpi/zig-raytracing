const util = @import("util.zig");
// General-purpose 3D vector. Reused as both a spatial `Point` and an RGB
// `Color` (see the `Point` alias below and `Color` in color.zig) since all
// three are just "three f64s with the same math" in this raytracer.
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
    // Dot product: sum of componentwise products. Used to project one vector
    // onto another (e.g. checking whether a ray points into or out of a
    // surface in hittable.zig) and to compute squared length below.
    pub fn dot(self: Vec3, other: Vec3) f64 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
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
    // magnitudes (or plug into the quadratic formula in sphere.zig) can skip
    // the sqrt entirely.
    pub fn lengthSquared(self: Vec3) f64 {
        return self.x * self.x + self.y * self.y + self.z * self.z;
    }

    // Same direction, magnitude 1. Used whenever we need just the direction
    // of a vector, e.g. the background gradient in camera.zig.
    pub fn unitVector(self: Vec3) Vec3 {
        return self.divide(self.length());
    }

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
};

// `Point` is just `Vec3` under a different name so code reads naturally
// (a sphere has a `center: Point`, a ray has a `direction: Vec3`) even
// though they're the same underlying type.
pub const Point = Vec3;
