const std = @import("std");
const vec3 = @import("vec3.zig");

// A ray is the line P(t) = origin + t * direction. Every pixel color in this
// renderer comes from tracing one (or more, for antialiasing) of these rays
// out from the camera and asking "what does it hit?".
pub const Ray = struct {
    origin: vec3.Point,
    direction: vec3.Vec3,

    // Returns the point along the ray at parameter t. t=0 is the origin; t=1
    // is one direction-vector's length further along. hittable.zig's
    // Sphere.hit() solves for the t of the intersection point, then calls this
    // to get the actual 3D coordinates.
    pub fn at(self: Ray, t: f64) vec3.Point {
        return self.origin + self.direction * vec3.splat(t);
    }
};

test "at walks along the ray" {
    const r = Ray{ .origin = vec3.init(1, 0, 0), .direction = vec3.init(0, 2, 0) };
    try std.testing.expectEqual(vec3.init(1, 0, 0), r.at(0));
    try std.testing.expectEqual(vec3.init(1, 2, 0), r.at(1));
    try std.testing.expectEqual(vec3.init(1, -1, 0), r.at(-0.5));
}
