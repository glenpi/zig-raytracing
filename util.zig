const std = @import("std");

// Fixed seed (29) rather than a time-based one, so renders are
// reproducible between runs — handy while developing/debugging, at the
// cost of every run producing the exact same antialiasing jitter pattern.
var prng = std.Random.DefaultPrng.init(29);
const rand = prng.random();

// Uniform random f64 in [0, 1).
pub fn randomDouble() f64 {
    return rand.float(f64);
}

// Uniform random f64 in [min, max).
pub fn randomDoubleWithRange(min: f64, max: f64) f64 {
    return min + (max - min) * randomDouble();
}

pub fn degreesToRadians(degrees: f64) f64 {
    return degrees * std.math.pi / 180.0;
}
