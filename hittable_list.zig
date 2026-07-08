const std = @import("std");
const hittable = @import("hittable.zig");
const ray = @import("ray.zig");
const interval = @import("interval.zig");

// The "world": a flat, growable list of every Hittable object in the scene.
// It is itself Hittable-shaped (has a `hit` method with the same signature)
// so the camera can treat "the whole world" the same way it would treat a
// single object.
pub const HittableList = struct {
    objects: std.ArrayList(hittable.Hittable),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HittableList {
        return .{ .objects = .empty, .allocator = allocator };
    }

    pub fn deinit(self: *HittableList) void {
        self.objects.deinit(self.allocator);
    }

    pub fn clear(self: *HittableList) void {
        self.objects.clearRetainingCapacity();
    }

    pub fn add(self: *HittableList, object: hittable.Hittable) !void {
        try self.objects.append(self.allocator, object);
    }

    // Finds the closest object the ray hits within ray_t, if any. Shrinking
    // the search interval's max to `closest_so_far` after each hit is what
    // makes this "closest" rather than "first found": once we know an
    // object was hit at distance t, any further object must be hit even
    // closer than that to matter, so we never need to reconsider farther
    // hits.
    pub fn hit(self: HittableList, r_in: ray.Ray, ray_t: interval.Interval, rec: *hittable.HitRecord) bool {
        var temp_rec: hittable.HitRecord = undefined;
        var hit_anything = false;
        var closest_so_far = ray_t.max;

        for (self.objects.items) |object| {
            if (object.hit(r_in, interval.Interval{ .min = ray_t.min, .max = closest_so_far }, &temp_rec)) {
                hit_anything = true;
                closest_so_far = temp_rec.t;
                rec.* = temp_rec;
            }
        }

        return hit_anything;
    }
};
