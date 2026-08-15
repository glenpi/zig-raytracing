const std = @import("std");

// Fixed seed (29) rather than a time-based one, so renders are reproducible
// between runs — handy while developing/debugging, at the cost of every run
// producing the exact same antialiasing jitter pattern.
//
// `threadlocal` because camera.render() farms scanlines out to worker threads:
// each one gets its own independent stream instead of racing on a shared one.
// Reproducibility survives because render() calls seedRandom() per scanline, so
// a row's samples don't depend on which worker picked it up.
//
// `prng.random()` is deliberately called per-use rather than cached in a
// container-level `const`: caching it would force the compiler to take the
// address of this mutable global at comptime, which happens to work today but
// breaks confusingly the moment the global moves or becomes const.
threadlocal var prng = std.Random.DefaultPrng.init(29);

// Restarts this thread's random stream from `s`. See the note above: the
// renderer uses it to make each scanline's samples a function of the row index
// alone.
pub fn seedRandom(s: u64) void {
    prng = .init(s);
}

// Uniform random f64 in [0, 1).
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
