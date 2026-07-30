const std = @import("std");
const hittable = @import("hittable.zig");
const ray = @import("ray.zig");
const vec3 = @import("vec3.zig");
const interval = @import("interval.zig");

// The "world": a flat, growable list of every Hittable object in the scene. It
// is itself Hittable-shaped (same `hit` signature) so the camera can treat "the
// whole world" the same way it would treat a single object.
pub const HittableList = struct {
    objects: std.ArrayList(hittable.Hittable),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HittableList {
        return .{ .objects = .empty, .allocator = allocator };
    }

    pub fn deinit(self: *HittableList) void {
        self.objects.deinit(self.allocator);
    }

    pub fn add(self: *HittableList, object: hittable.Hittable) !void {
        try self.objects.append(self.allocator, object);
    }

    // Finds the closest object the ray hits within ray_t, if any. Shrinking the
    // search interval's max to the closest hit so far is what makes this
    // "closest" rather than "first found": once we know an object was hit at
    // distance t, any further object must be hit even closer than that to
    // matter, so we never need to reconsider farther hits.
    pub fn hit(self: HittableList, r_in: ray.Ray, ray_t: interval.Interval) ?hittable.HitRecord {
        var closest: ?hittable.HitRecord = null;

        for (self.objects.items) |object| {
            const max = if (closest) |c| c.t else ray_t.max;
            if (object.hit(r_in, .{ .min = ray_t.min, .max = max })) |rec| closest = rec;
        }

        return closest;
    }
};

test "hit returns the closest of several overlapping spheres" {
    const mat = @import("material.zig").Material{ .lambertian = .{ .albedo = vec3.splat(0.5) } };
    var world = HittableList.init(std.testing.allocator);
    defer world.deinit();

    // Three spheres along +z. Fired from the origin toward +z, the one at z=2
    // is nearest, so its surface at z=1 (t=1) must win regardless of add order.
    try world.add(.{ .sphere = .{ .center = vec3.init(0, 0, 6), .radius = 1, .mat = mat } });
    try world.add(.{ .sphere = .{ .center = vec3.init(0, 0, 2), .radius = 1, .mat = mat } });
    try world.add(.{ .sphere = .{ .center = vec3.init(0, 0, 4), .radius = 1, .mat = mat } });

    const r = ray.Ray{ .origin = vec3.zero, .direction = vec3.init(0, 0, 1) };
    const rec = world.hit(r, .{ .min = 0.001, .max = std.math.inf(f64) }).?;
    try std.testing.expectApproxEqAbs(@as(f64, 1), rec.t, 1e-12);
}

test "an empty world and a total miss both return null" {
    var world = HittableList.init(std.testing.allocator);
    defer world.deinit();

    const r = ray.Ray{ .origin = vec3.zero, .direction = vec3.init(0, 0, 1) };
    const everything = interval.Interval{ .min = 0.001, .max = std.math.inf(f64) };
    try std.testing.expectEqual(@as(?hittable.HitRecord, null), world.hit(r, everything));

    const mat = @import("material.zig").Material{ .lambertian = .{ .albedo = vec3.splat(0.5) } };
    try world.add(.{ .sphere = .{ .center = vec3.init(0, 50, 0), .radius = 1, .mat = mat } });
    try std.testing.expectEqual(@as(?hittable.HitRecord, null), world.hit(r, everything));
}
