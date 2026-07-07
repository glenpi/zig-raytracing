const std = @import("std");
var prng = std.Random.DefaultPrng.init(29);
const rand = prng.random();

pub fn randomDouble() f64 {
    return rand.float(f64);
}

pub fn randomDoubleWithRange(min: f64, max: f64) f64 {
    return min + (max - min) * randomDouble();
}
