const std = @import("std");
const memory = @import("./memory.zig");
const common = @import("./common.zig");
const VM = @import("./vm.zig").VM;
const Value = @import("./value.zig").Value;
const Chunk = @import("./chunk.zig").Chunk;
const alloc = common.alloc;

pub const ObjType = enum(u8) { obj_string, obj_function };

pub const Obj = extern struct {
    const Self = @This();
    t: ObjType,
    next: ?*Obj = undefined,

    pub fn asString(self: *Self) *ObjString {
        return @ptrCast(*ObjString, @alignCast(@alignOf(ObjString), self));
    }

    pub fn asFunction(self: *Self) *ObjFunction {
        return @ptrCast(*ObjFunction, @alignCast(@alignOf(ObjFunction), self));
    }

    pub fn print(self: *Self, writer: anytype) void {
        switch (self.t) {
            .obj_string => {
                writer.print("{s}", .{self.asString().chars[0..self.asString().length]}) catch unreachable;
            },
            .obj_function => {
                printFunction(self.asFunction(), writer);
            },
        }
    }
};

pub const ObjFunction = extern struct {
    obj: Obj,
    arity: usize,
    _chunk: [@sizeOf(Chunk)]u8 align(@alignOf(Chunk)) = undefined,
    name: ?*ObjString,
    pub inline fn chunk(self: *ObjFunction) *Chunk {
        return @ptrCast(*Chunk, &self._chunk);
    }
};

pub const ObjString = extern struct {
    obj: Obj,
    length: usize,
    chars: [*]u8,
    hash: u32,
};

pub fn newFunction() *ObjFunction {
    var function = allocateObject(ObjFunction, .obj_function);
    function.arity = 0;
    function.name = null;
    function.chunk().* = Chunk.init(alloc);
    return function;
}

pub fn copyString(chars: [*]const u8, length: usize) *Obj {
    const hash = hashString(chars, length);
    const interned = VM.strings.findString(chars, length, hash);
    var string: *ObjString = undefined;
    if (interned) |i| {
        string = i;
    } else {
        var heap_chars = memory.allocate(u8, length + 1, alloc)[0 .. length + 1];
        std.mem.copy(u8, heap_chars, chars[0..length]);
        heap_chars[length] = 0;
        string = allocateString(heap_chars[0..length], hash);
    }

    return @ptrCast(*Obj, string);
}

pub fn takeString(chars: [*]u8, length: usize) *Obj {
    const hash = hashString(chars, length);
    const interned = VM.strings.findString(chars, length, hash);
    var string: *ObjString = undefined;
    if (interned) |i| {
        memory.freeArray(u8, chars, length + 1, alloc);
        string = i;
    } else {
        string = allocateString(chars[0..length], hash);
    }
    return @ptrCast(*Obj, string);
}

fn printFunction(function: *ObjFunction, writer: anytype) void {
    if (function.name) |name| {
        writer.print("<fn {s}>", .{name.chars[0..name.length]}) catch unreachable;
    } else {
        writer.print("<script>", .{}) catch unreachable;
    }
}

fn allocateString(chars: []u8, hash: u32) *ObjString {
    var string = allocateObject(ObjString, .obj_string);
    string.length = chars.len;
    string.chars = chars.ptr;
    string.hash = hash;
    _ = VM.strings.tableSet(string, Value.Nil());
    return string;
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
