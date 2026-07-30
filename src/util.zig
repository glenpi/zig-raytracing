const std = @import("std");

// Fixed seed (29) rather than a time-based one, so renders are reproducible
// between runs — handy while developing/debugging, at the cost of every run
// producing the exact same antialiasing jitter pattern.
//
// `prng.random()` is deliberately called per-use rather than cached in a
// container-level `const`: caching it would force the compiler to take the
// address of this mutable global at comptime, which happens to work today but
// breaks confusingly the moment the global moves or becomes const.
var prng = std.Random.DefaultPrng.init(29);

// Uniform random f64 in [0, 1).
//
// ponytail: one global PRNG, so the renderer has to stay single-threaded.
// Give each worker its own DefaultPrng (seeded per row) if render() is ever
// parallelised.
pub fn randomDouble() f64 {
    return prng.random().float(f64);
}

// Uniform random f64 in [min, max).
pub fn randomDoubleWithRange(min: f64, max: f64) f64 {
    return min + (max - min) * randomDouble();
}

pub fn degreesToRadians(degrees: f64) f64 {
    return degrees * std.math.pi / 180.0;
}

test "randomDouble stays in [0, 1) and averages near 0.5" {
    var sum: f64 = 0;
    for (0..100_000) |_| {
        const v = randomDouble();
        try std.testing.expect(0 <= v and v < 1);
        sum += v;
    }
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), sum / 100_000, 0.01);
}

test "randomDoubleWithRange respects its bounds" {
    for (0..10_000) |_| {
        const v = randomDoubleWithRange(-3, 7);
        try std.testing.expect(-3 <= v and v < 7);
    }
}

test "degreesToRadians" {
    try std.testing.expectApproxEqAbs(std.math.pi, degreesToRadians(180), 1e-15);
    try std.testing.expectApproxEqAbs(std.math.pi / 2.0, degreesToRadians(90), 1e-15);
}
