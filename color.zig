const std = @import("std");
const vec3 = @import("vec3.zig");
const interval = @import("interval.zig");

// A color is just a Vec3 whose x/y/z are read as r/g/b in [0, 1] (before
// this file converts them to 0-255 bytes for the PPM image format).
pub const Color = vec3.Vec3;

// Writes one pixel as "r g b\n" in the PPM P3 text format (see main.zig,
// which prints the "P3 / width height / 255" header once before calling
// this per pixel).
pub fn writeColor(writer: *std.Io.Writer, c: Color) !void {
    // Averaged/antialiased samples can slightly exceed 1.0; clamp to
    // [0, 0.999] so 255.999 * value never rounds up to 256.
    const intensity = interval.Interval{
        .min = 0.0,
        .max = 0.999,
    };

    const r = linearToGamma(c.x);
    const g = linearToGamma(c.y);
    const b = linearToGamma(c.z);

    const rbyte: u8 = @intFromFloat(255.999 * intensity.clamp(r));
    const gbyte: u8 = @intFromFloat(255.999 * intensity.clamp(g));
    const bbyte: u8 = @intFromFloat(255.999 * intensity.clamp(b));

    try writer.print("{} {} {}\n", .{ rbyte, gbyte, bbyte });
}

pub fn linearToGamma(linear_component: f64) f64 {
    if (linear_component > 0) {
        return @sqrt(linear_component);
    }
    return 0;
}
