const std = @import("std");

// A range of ray-parameter `t` values that count as a valid hit. Threaded
// through every `hit()` call: hittable_list.zig narrows its `max` to the
// closest hit found so far, and camera.zig starts it at 0.001 rather than 0 to
// avoid "shadow acne".
pub const Interval = struct {
    min: f64,
    max: f64,

    // Exclusive of both endpoints, so a hit exactly at the ray's own boundary
    // (e.g. t=0) doesn't count.
    pub fn surrounds(self: Interval, x: f64) bool {
        return self.min < x and x < self.max;
    }
};

test "surrounds excludes the endpoints" {
    const i = Interval{ .min = 0, .max = 1 };
    try std.testing.expect(i.surrounds(0.5));
    try std.testing.expect(!i.surrounds(0));
    try std.testing.expect(!i.surrounds(1));
    try std.testing.expect(!i.surrounds(-0.1));
}
