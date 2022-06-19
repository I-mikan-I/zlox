const std = @import("std");
const memory = @import("./memory.zig");
const table = @import("./table.zig");
const common = @import("./common.zig");
const VM = @import("./vm.zig").VM;
const Value = @import("./value.zig").Value;
const Chunk = @import("./chunk.zig").Chunk;
const Table = table.Table;
const alloc = common.alloc;

var vm: *VM = undefined;

pub fn initGC(_vm: *VM) void {
    vm = _vm;
}

pub const ObjType = enum(u8) { obj_string, obj_function, obj_native, obj_closure, obj_upvalue, obj_class, obj_instance };

pub const Obj = extern struct {
    const Self = @This();
    t: ObjType,
    is_marked: bool,
    next: ?*Obj = null,

    pub fn asString(self: *Self) *ObjString {
        return @ptrCast(*ObjString, @alignCast(@alignOf(ObjString), self));
    }

    pub fn asFunction(self: *Self) *ObjFunction {
        return @ptrCast(*ObjFunction, @alignCast(@alignOf(ObjFunction), self));
    }

    pub fn asNative(self: *Self) *ObjNative {
        return @ptrCast(*ObjNative, @alignCast(@alignOf(ObjNative), self));
    }

    pub fn asClosure(self: *Self) *ObjClosure {
        return @ptrCast(*ObjClosure, @alignCast(@alignOf(ObjClosure), self));
    }

    pub fn asUpvalue(self: *Self) *ObjUpvalue {
        return @ptrCast(*ObjUpvalue, @alignCast(@alignOf(ObjUpvalue), self));
    }

    pub fn asClass(self: *Self) *ObjClass {
        return @ptrCast(*ObjClass, @alignCast(@alignOf(ObjClass), self));
    }

    pub fn asInstance(self: *Self) *ObjInstance {
        return @ptrCast(*ObjInstance, @alignCast(@alignOf(ObjInstance), self));
    }

    pub fn print(self: *Self, writer: anytype) void {
        switch (self.t) {
            .obj_string => {
                writer.print("{s}", .{self.asString().chars[0..self.asString().length]}) catch unreachable;
            },
            .obj_function => {
                printFunction(self.asFunction(), writer);
            },
            .obj_native => {
                writer.print("<native fn>", .{}) catch unreachable;
            },
            .obj_closure => {
                printFunction(self.asClosure().function, writer);
            },
            .obj_upvalue => {
                writer.print("upvalue", .{}) catch unreachable;
            },
            .obj_class => {
                writer.print("{s}", .{self.asClass().name.chars[0..self.asClass().name.length]}) catch unreachable;
            },
            .obj_instance => {
                writer.print("{s} instance", .{self.asInstance().class.name.chars[0..self.asInstance().class.name.length]}) catch unreachable;
            },
        }
    }
};

pub const ObjFunction = extern struct {
    obj: Obj,
    arity: usize,
    _chunk: [@sizeOf(Chunk)]u8 align(@alignOf(Chunk)) = undefined,
    name: ?*ObjString,
    upvalue_count: u8,
    pub inline fn chunk(self: *ObjFunction) *Chunk {
        return @ptrCast(*Chunk, &self._chunk);
    }
};

pub const ObjClosure = extern struct {
    obj: Obj,
    function: *ObjFunction,
    upvalues: [*]?*ObjUpvalue,
    upvalue_count: usize,
};

pub const ObjClass = extern struct {
    obj: Obj,
    name: *ObjString,
};

pub const ObjInstance = extern struct {
    obj: Obj,
    class: *ObjClass,
    _fields: [@sizeOf(Table)]u8 align(@alignOf(Table)),

    pub inline fn fields(self: *ObjInstance) *Table {
        return @ptrCast(*Table, &self._fields);
    }
};

pub const NativeFn = fn (arg_count: usize, args: [*]Value) Value;

pub const ObjNative = extern struct {
    obj: Obj,
    _function: [@sizeOf(NativeFn)]u8 align(@alignOf(NativeFn)) = undefined,

    pub inline fn function(self: *ObjNative) *NativeFn {
        return @ptrCast(*NativeFn, &self._function);
    }
};

pub const ObjString = extern struct {
    obj: Obj,
    length: usize,
    chars: [*]u8,
    hash: u32,
};

pub const ObjUpvalue = extern struct {
    obj: Obj,
    location: *Value,
    next: ?*ObjUpvalue,
    _closed: [@sizeOf(Value)]u8 align(@alignOf(Value)),

    pub inline fn closed(self: *ObjUpvalue) *Value {
        return @ptrCast(*Value, &self._closed);
    }
};

pub fn newInstance(class: *ObjClass) *Obj {
    const instance = allocateObject(ObjInstance, .obj_instance);
    instance.class = class;
    instance.fields().* = Table.initTable();
    return @ptrCast(*Obj, instance);
}

pub fn newClass(name: *ObjString) *Obj {
    const class = allocateObject(ObjClass, .obj_class);
    class.name = name;
    return @ptrCast(*Obj, class);
}

pub fn newClosure(function: *ObjFunction) *ObjClosure {
    const upvalues = memory.allocate(?*ObjUpvalue, function.upvalue_count);
    for (upvalues[0..function.upvalue_count]) |*upvalue| {
        upvalue.* = null;
    }
    var closure = allocateObject(ObjClosure, .obj_closure);
    closure.upvalues = upvalues;
    closure.upvalue_count = function.upvalue_count;
    closure.function = function;
    return closure;
}

pub fn newFunction() *ObjFunction {
    var function = allocateObject(ObjFunction, .obj_function);
    function.arity = 0;
    function.name = null;
    function.chunk().* = Chunk.init(alloc);
    function.upvalue_count = 0;
    return function;
}

pub fn newNative(function: NativeFn) *Obj {
    var native = allocateObject(ObjNative, .obj_native);
    native.function().* = function;
    return @ptrCast(*Obj, native);
}

pub fn newUpvalue(slot: *Value) *ObjUpvalue {
    var upvalue = allocateObject(ObjUpvalue, .obj_upvalue);
    upvalue.location = slot;
    upvalue.next = null;
    upvalue.closed().* = Value.Nil();
    return upvalue;
}

pub fn copyString(chars: [*]const u8, length: usize) *Obj {
    const hash = hashString(chars, length);
    const interned = VM.strings.findString(chars, length, hash);
    var string: *ObjString = undefined;
    if (interned) |i| {
        string = i;
    } else {
        var heap_chars = memory.allocate(u8, length + 1)[0 .. length + 1];
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
        memory.freeArray(u8, chars, length + 1);
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
    vm.push(Value.Object(@ptrCast(*Obj, string)));
    _ = VM.strings.tableSet(string, Value.Nil());
    _ = vm.pop();
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
    var obj = &memory.allocate(t, 1)[0];
    obj.obj.t = obj_t;
    obj.obj.is_marked = false;
    obj.obj.next = VM.objects;
    VM.objects = &obj.obj;

    if (comptime common.log_gc) {
        const stdout = common.stdout;
        stdout.print("{*} allocate {d} for {any}\n", .{ obj, @sizeOf(t), obj_t }) catch unreachable;
    }

    return obj;
}
