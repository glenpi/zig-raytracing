const rtweekend = @import("rtweekend.zig");

// `empty`/`universe` deliberately invert min/max so that no real value ever
// falls inside `empty` (min > max, so contains()/surrounds() are always
// false), and every value falls inside `universe`.
pub const empty = Interval{ .min = rtweekend.infinity, .max = -rtweekend.infinity };

pub const universe = Interval{
    .min = -rtweekend.infinity,
    .max = rtweekend.infinity,
};

// A closed range [min, max] of f64. Used two ways in this raytracer:
// 1. Restricting which ray-parameter `t` values count as a valid hit
//    (see hittable_list.zig / sphere.zig) — this is what avoids "shadow acne"
//    from a hit at t~0 and lets us track the closest hit so far.
// 2. Clamping a color channel into [0, 1] before writing it out (color.zig).
pub const Interval = struct {
    min: f64 = rtweekend.infinity,
    max: f64 = -rtweekend.infinity,

    pub fn size(self: Interval) f64 {
        return self.max - self.min;
    }
    // Inclusive of both endpoints.
    pub fn contains(self: Interval, x: f64) bool {
        return self.min <= x and x <= self.max;
    }
    // Exclusive of both endpoints — used for hit tests so a hit exactly at
    // the ray's own boundary (e.g. t=0) doesn't count.
    pub fn surrounds(self: Interval, x: f64) bool {
        return self.min < x and x < self.max;
    }
    pub fn clamp(self: Interval, x: f64) f64 {
        if (x < self.min) {
            return self.min;
        }
        if (x > self.max) {
            return self.max;
        }
        return x;
    }
};
