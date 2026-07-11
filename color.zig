const std = @import("std");
const vec3 = @import("vec3.zig");
const interval = @import("interval.zig");

// A color is just a Vec3 whose x/y/z are read as r/g/b in [0, 1] (before
// this file converts them to 0-255 bytes for the PPM image format). The
// alias itself lives in vec3.zig next to `Point`; re-exported here so
// `color.Color` keeps working for callers of this file.
pub const Color = vec3.Color;

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

// Converts a color computed in linear light space to gamma-2 space (the
// convention monitors and image viewers expect) via sqrt, which approximates
// raising to the power 1/2. Without this, renders look noticeably too dark,
// since linear values map non-linearly to perceived brightness.
pub fn linearToGamma(linear_component: f64) f64 {
    if (linear_component > 0) {
        return @sqrt(linear_component);
    }
    return 0;
}
