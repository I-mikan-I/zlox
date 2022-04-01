const std = @import("std");
pub fn growArray(t: type, ptr: [*]u8, old_cap: u32, new_cap: u32, alloc: std.mem.Allocator) ?[*]t {
   return reallocate(ptr, old_cap, new_cap, alloc);
}

fn reallocate(pointer: anytype, old_size: usize, new_size: usize, alloc: std.mem.Allocator) ?@TypeOf(pointer) {
    if (@typeInfo(pointer) != .Pointer) {
        unreachable;
    }
    if (new_size == 0) {
        alloc.free(pointer);
        return null;
    }
    if (old_size == 0) {
        alloc.alloc(@typeInfo(pointer).Pointer.child, new_size);
        return null;
    }
    return alloc.realloc(pointer, new_size) catch std.os.exit(1);
}
