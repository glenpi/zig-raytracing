const std = @import("std");
const util = @import("util.zig");

// General-purpose 3D vector, built on Zig's builtin SIMD vector type so the
// arithmetic operators (+ - * /) and @sqrt/@abs/@reduce work directly on it.
// Reused as both a spatial `Point` and an RGB `Color` (see the aliases at the
// bottom) since all three are just "three f64s with the same math" here.
pub const Vec3 = @Vector(3, f64);

pub const zero: Vec3 = @splat(0);

// Componentwise construction. `Vec3{ x, y, z }` also works, but naming the
// axes reads better at call sites that mean a point in space.
pub fn init(x: f64, y: f64, z: f64) Vec3 {
    return .{ x, y, z };
}

// Broadcasts a scalar across all three lanes, so `v * splat(t)` scales v.
pub fn splat(t: f64) Vec3 {
    return @splat(t);
}

// Dot product: sum of componentwise products. Used to project one vector onto
// another (e.g. checking whether a ray points into or out of a surface in
// hittable.zig) and to compute squared length below.
pub fn dot(u: Vec3, v: Vec3) f64 {
    const p = u * v;
    return p[0] + p[1] + p[2];
}

// Cross product: a vector perpendicular to both u and v, used to derive the
// camera's "right" basis vector from vup and the view direction (see
// camera.zig's initialize()).
pub fn cross(u: Vec3, v: Vec3) Vec3 {
    return .{
        u[1] * v[2] - u[2] * v[1],
        u[2] * v[0] - u[0] * v[2],
        u[0] * v[1] - u[1] * v[0],
    };
}

pub fn length(v: Vec3) f64 {
    return @sqrt(lengthSquared(v));
}

// Kept separate from length() because callers that only need to compare
// magnitudes (or plug into the quadratic formula in hittable.zig's
// Sphere.hit()) can skip the sqrt entirely.
pub fn lengthSquared(v: Vec3) f64 {
    return dot(v, v);
}

// Same direction, magnitude 1. Used whenever we need just the direction of a
// vector, e.g. the background gradient in camera.zig.
pub fn unitVector(v: Vec3) Vec3 {
    return v / splat(length(v));
}

// Rejection sampling: pick a random point in the [-1,1] x [-1,1] square (z=0)
// and keep it only if it also falls inside the unit circle; otherwise try
// again. Simpler than deriving a direct formula for a uniform distribution
// over a disk, and fast since the square is only ~27% bigger in area than the
// circle it contains. Used for camera.zig's defocus-disk (depth-of-field)
// sampling.
pub fn randomInUnitDisk() Vec3 {
    while (true) {
        const p = init(util.randomDoubleWithRange(-1, 1), util.randomDoubleWithRange(-1, 1), 0);
        if (lengthSquared(p) < 1) return p;
    }
}

// Same rejection-sampling idea as randomInUnitDisk, but in 3D and then
// normalized to land exactly on the unit sphere's surface, giving a uniformly
// random direction. The lower bound 1e-160 guards against dividing by (near)
// zero when a sampled point lands extremely close to the origin, which would
// otherwise blow up to infinity/NaN.
pub fn randomUnitVector() Vec3 {
    while (true) {
        const p = randomWithRange(-1, 1);
        const lensq = lengthSquared(p);
        if (1e-160 < lensq and lensq <= 1) {
            return p / splat(@sqrt(lensq));
        }
    }
}

// A random unit vector in the hemisphere facing `normal`. This is the book's
// first, uniform diffuse bounce (images 7 to 9), before cosine weighting.
pub fn randomOnHemisphere(normal: Vec3) Vec3 {
    const v = randomUnitVector();
    return if (dot(v, normal) > 0) v else -v;
}

pub fn random() Vec3 {
    return init(util.randomDouble(), util.randomDouble(), util.randomDouble());
}

pub fn randomWithRange(min: f64, max: f64) Vec3 {
    return init(
        util.randomDoubleWithRange(min, max),
        util.randomDoubleWithRange(min, max),
        util.randomDoubleWithRange(min, max),
    );
}

// True if every component is within a tiny epsilon of 0. Used by
// Lambertian.scatter() (material.zig) to detect the degenerate case where a
// random scatter direction almost exactly cancels the surface normal, which
// would otherwise produce a zero-length ray direction.
pub fn nearZero(v: Vec3) bool {
    return @reduce(.And, @abs(v) < splat(1e-8));
}

// Mirror reflection of v about normal n: v minus twice its projection onto n.
// (The projection length is dot(v, n) since n is unit length.)
pub fn reflect(v: Vec3, n: Vec3) Vec3 {
    return v - n * splat(dot(v, n)) * splat(2);
}

// Snell's law, split into the refracted ray's components perpendicular and
// parallel to the surface normal, then recombined.
pub fn refract(uv: Vec3, n: Vec3, etai_over_etat: f64) Vec3 {
    const cos_theta = @min(dot(-uv, n), 1.0);
    const r_out_perp = (uv + n * splat(cos_theta)) * splat(etai_over_etat);
    const r_out_parallel = n * splat(-@sqrt(@abs(1 - lengthSquared(r_out_perp))));
    return r_out_perp + r_out_parallel;
}

// Both aliases are just `Vec3` under a different name so code reads naturally
// (a sphere has a `center: Point`, a material has an `albedo: Color`, a ray
// has a `direction: Vec3`) even though all three are the exact same type.
pub const Point = Vec3;
pub const Color = Vec3;

test "dot, cross and length" {
    const x = init(1, 0, 0);
    const y = init(0, 1, 0);
    try std.testing.expectEqual(@as(f64, 0), dot(x, y));
    try std.testing.expectEqual(init(0, 0, 1), cross(x, y));
    try std.testing.expectEqual(@as(f64, 5), length(init(3, 4, 0)));
    try std.testing.expectEqual(init(1, 0, 0), unitVector(init(7, 0, 0)));
}

test "reflect bounces off a flat surface" {
    // Straight down onto an upward-facing surface comes straight back up.
    try std.testing.expectEqual(init(0, 1, 0), reflect(init(0, -1, 0), init(0, 1, 0)));
    // A 45-degree incoming ray leaves at 45 degrees, x preserved.
    const d = reflect(unitVector(init(1, -1, 0)), init(0, 1, 0));
    try std.testing.expectApproxEqAbs(@as(f64, 1), length(d), 1e-12);
    try std.testing.expectApproxEqAbs(@sqrt(0.5), d[0], 1e-12);
    try std.testing.expectApproxEqAbs(@sqrt(0.5), d[1], 1e-12);
}

test "refract straight through is unbent, and stays unit length" {
    const straight = refract(init(0, -1, 0), init(0, 1, 0), 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0), straight[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -1), straight[1], 1e-12);

    // Entering a denser medium (ratio < 1) bends the ray toward the normal,
    // i.e. the horizontal component shrinks.
    const uv = unitVector(init(1, -1, 0));
    const bent = refract(uv, init(0, 1, 0), 1.0 / 1.5);
    try std.testing.expect(@abs(bent[0]) < @abs(uv[0]));
    try std.testing.expectApproxEqAbs(@as(f64, 1), length(bent), 1e-12);
}

test "nearZero only fires on genuinely tiny vectors" {
    try std.testing.expect(nearZero(zero));
    try std.testing.expect(nearZero(init(1e-9, -1e-9, 0)));
    try std.testing.expect(!nearZero(init(1e-7, 0, 0)));
}

test "random samples land inside their bounds" {
    for (0..1000) |_| {
        try std.testing.expect(lengthSquared(randomInUnitDisk()) < 1);
        try std.testing.expectApproxEqAbs(@as(f64, 1), length(randomUnitVector()), 1e-12);
        try std.testing.expect(@reduce(.And, @abs(randomWithRange(-1, 1)) <= splat(1.0)));
    }
}
