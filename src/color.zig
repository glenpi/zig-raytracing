const std = @import("std");
const vec3 = @import("vec3.zig");

// Averaged/antialiased samples can slightly exceed 1.0; clamp to [0, 0.999] so
// 255.999 * value never rounds up to 256.
const max_intensity = 0.999;

// Writes one pixel as "r g b\n" in the PPM P3 text format (see camera.zig,
// which prints the "P3 / width height / 255" header once before calling this
// per pixel).
pub fn writeColor(writer: *std.Io.Writer, c: vec3.Color) !void {
    const bytes = toBytes(c);
    try writer.print("{} {} {}\n", .{ bytes[0], bytes[1], bytes[2] });
}

// Gamma-corrects, clamps and quantises a linear color to three 0-255 bytes.
// Split out from writeColor so it can be tested without a writer.
pub fn toBytes(c: vec3.Color) [3]u8 {
    const gamma = linearToGamma(c);
    const clamped = std.math.clamp(gamma, vec3.zero, vec3.splat(max_intensity));
    const scaled = clamped * vec3.splat(255.999);
    return .{
        @intFromFloat(scaled[0]),
        @intFromFloat(scaled[1]),
        @intFromFloat(scaled[2]),
    };
}

// Converts a color computed in linear light space to gamma-2 space (the
// convention monitors and image viewers expect) via sqrt, which approximates
// raising to the power 1/2. Without this, renders look noticeably too dark,
// since linear values map non-linearly to perceived brightness.
//
// The `> 0` select also swallows NaN, which keeps the @intFromFloat in
// toBytes() from tripping over an unrepresentable value.
pub fn linearToGamma(linear: vec3.Color) vec3.Color {
    return @select(f64, linear > vec3.zero, @sqrt(linear), vec3.zero);
}

test "toBytes gamma-corrects and quantises" {
    // Black and white are the fixed points of sqrt, so they map to the ends.
    try std.testing.expectEqual([3]u8{ 0, 0, 0 }, toBytes(vec3.zero));
    try std.testing.expectEqual([3]u8{ 255, 255, 255 }, toBytes(vec3.splat(1)));
    // 0.25 linear -> 0.5 gamma -> 127.
    try std.testing.expectEqual([3]u8{ 127, 127, 127 }, toBytes(vec3.splat(0.25)));
}

test "toBytes clamps out-of-range channels instead of overflowing u8" {
    try std.testing.expectEqual([3]u8{ 255, 0, 0 }, toBytes(vec3.init(4, -1, 0)));
    // NaN is swallowed by linearToGamma rather than reaching @intFromFloat.
    try std.testing.expectEqual([3]u8{ 0, 0, 0 }, toBytes(vec3.splat(std.math.nan(f64))));
}
