const std = @import("std");
const memory = @import("./memory.zig");
const common = @import("./common.zig");
const VM = @import("./vm.zig").VM;
const alloc = common.alloc;

pub const ObjType = enum {
    obj_string,
};

pub const Obj = packed struct {
    const Self = @This();
    t: ObjType,
    next: ?*Obj = undefined,

    pub fn asString(self: *Self) *ObjString {
        return @ptrCast(*ObjString, self);
    }

    pub fn print(self: *Self, writer: anytype) void {
        switch (self.t) {
            .obj_string => {
                writer.print("{s}", .{self.asString().chars[0..self.asString().length]}) catch unreachable;
            },
        }
    }
};

pub const ObjString = packed struct {
    obj: Obj,
    _1: [@sizeOf(Obj) % @sizeOf(usize)]u8 = undefined,
    length: usize,
    chars: [*]u8,
    hash: u32,
};

pub fn copyString(chars: [*]const u8, length: usize) *Obj {
    const hash = hashString(chars, length);
    var heap_chars = memory.allocate(u8, length + 1, alloc)[0 .. length + 1];
    std.mem.copy(u8, heap_chars, chars[0..length]);
    heap_chars[length] = 0;
    return @ptrCast(*Obj, allocateString(heap_chars, hash));
}

fn allocateString(chars: []u8, hash: u32) *ObjString {
    var string = allocateObject(ObjString, .obj_string);
    string.length = chars.len;
    string.chars = chars.ptr;
    string.hash = hash;
    return string;
}

pub fn takeString(chars: [*]u8, length: usize) *Obj {
    const hash = hashString(chars, length);
    return @ptrCast(*Obj, allocateString(chars[0..length], hash));
}

fn hashString(key: [*]const u8, length: usize) u32 {
    var hash: u32 = 2166136261;
    var i: usize = 0;
    while (i < length) : (i += 1) {
        hash ^= key[i];
        hash *%= 16777619;
    }
    return hash;
}

fn allocateObject(comptime t: type, obj_t: ObjType) *t {
    var obj = &memory.allocate(t, 1, alloc)[0];
    obj.obj.t = obj_t;
    obj.obj.next = VM.objects;
    VM.objects = &obj.obj;
    return obj;
}
