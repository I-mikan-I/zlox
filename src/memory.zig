const std = @import("std");

pub fn growArray(comptime t: type, ptr: [*]t, old_cap: u32, new_cap: u32, alloc: std.mem.Allocator) [*]t {
    return reallocate(ptr, old_cap, new_cap, alloc) orelse ptr;
}

pub fn freeArray(comptime t: type, ptr: [*]t, old_count: u32, alloc: std.mem.Allocator) void {
    _ = reallocate(ptr, old_count, 0, alloc);
    return;
}

fn reallocate(pointer: anytype, old_size: usize, new_size: usize, alloc: std.mem.Allocator) ?@TypeOf(pointer) {
    const info = @typeInfo(@TypeOf(pointer));
    if (info != .Pointer) {
        unreachable;
    }
    if (new_size == 0) {
        alloc.free(pointer[0..old_size]);
        return null;
    }
    if (old_size == 0) {
        return (alloc.alloc(info.Pointer.child, new_size) catch std.os.exit(1)).ptr;
    }
    return (alloc.realloc(pointer[0..old_size], new_size) catch std.os.exit(1)).ptr;
}
