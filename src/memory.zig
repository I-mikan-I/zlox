const std = @import("std");
const VM = @import("./vm.zig").VM;
const object = @import("./object.zig");
const Obj = object.Obj;
const ObjString = object.ObjString;

pub fn growArray(comptime t: type, ptr: [*]t, old_cap: u32, new_cap: u32, alloc: std.mem.Allocator) [*]t {
    return reallocate(ptr, old_cap, new_cap, alloc) orelse ptr;
}

pub fn freeArray(comptime t: type, ptr: [*]t, old_count: usize, alloc: std.mem.Allocator) void {
    _ = reallocate(ptr, old_count, 0, alloc);
    return;
}

fn free(comptime t: type, ptr: *t, alloc: std.mem.Allocator) void {
    _ = reallocate(@ptrCast([*]t, ptr), 1, 0, alloc);
    return;
}

pub fn allocate(comptime t: type, count: usize, alloc: std.mem.Allocator) [*]t {
    if (count < 1) unreachable;
    var tmp: [*]t = undefined;
    return reallocate(tmp, 0, count, alloc).?;
}

pub fn reallocate(pointer: anytype, old_size: usize, new_size: usize, alloc: std.mem.Allocator) ?@TypeOf(pointer) {
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

pub fn freeObjects(alloc: std.mem.Allocator) void {
    var obj = VM.objects;
    while (obj) |o| {
        const next = o.next;
        freeObject(o, alloc);
        obj = next;
    }
    VM.objects = null;
}

fn freeObject(o: *Obj, alloc: std.mem.Allocator) void {
    switch (o.t) {
        .obj_string => {
            const str = o.asString();
            freeArray(u8, str.chars, str.length + 1, alloc);
            free(ObjString, str, alloc);
        },
    }
}
