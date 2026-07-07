const vec = @import("vec3.zig");
const Point = vec.Point;
const Vec3 = vec.Vec3;

// A ray is the line P(t) = origin + t * direction. Every pixel color in this
// renderer comes from tracing one (or more, for antialiasing) of these rays
// out from the camera and asking "what does it hit?".
pub const Ray = struct {
    origin: Point,
    direction: Vec3,

    // Returns the point along the ray at parameter t. t=0 is the origin;
    // t=1 is one direction-vector's length further along. sphere.zig solves
    // for the t of the intersection point, then calls this to get the
    // actual 3D coordinates.
    pub fn at(self: Ray, t: f64) Point {
        return self.origin.add(self.direction.multiply(t));
    }
};
