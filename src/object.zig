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
};

pub fn copyString(chars: [*]const u8, length: usize) *Obj {
    var heap_chars = memory.allocate(u8, length + 1, alloc)[0 .. length + 1];
    std.mem.copy(u8, heap_chars, chars[0..length]);
    heap_chars[length] = 0;
    return @ptrCast(*Obj, allocateString(heap_chars));
}

fn allocateString(chars: []u8) *ObjString {
    var string = allocateObject(ObjString, .obj_string);
    string.length = chars.len;
    string.chars = chars.ptr;
    return string;
}

pub fn takeString(chars: [*]u8, length: usize) *Obj {
    return @ptrCast(*Obj, allocateString(chars[0..length]));
}

fn allocateObject(comptime t: type, obj_t: ObjType) *t {
    var obj = &memory.allocate(t, 1, alloc)[0];
    obj.obj.t = obj_t;
    obj.obj.next = VM.objects;
    VM.objects = &obj.obj;
    return obj;
}
