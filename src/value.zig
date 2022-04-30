const std = @import("std");
const memory = @import("./memory.zig");
const object = @import("./object.zig");
const Obj = object.Obj;

pub const ValueType = enum {
    val_bool,
    val_nil,
    val_number,
    val_obj,
};

pub const Value = struct {
    t: ValueType,
    as: union {
        boolean: bool,
        number: f64,
        obj: *Obj,
    },

    pub inline fn Boolean(value: bool) Value {
        return .{ .t = .val_bool, .as = .{
            .boolean = value,
        } };
    }
    pub inline fn Nil() Value {
        return .{ .t = .val_nil, .as = .{
            .number = 0,
        } };
    }
    pub inline fn Number(value: f64) Value {
        return .{ .t = .val_number, .as = .{
            .number = value,
        } };
    }
    pub inline fn Object(obj: *Obj) Value {
        return .{ .t = .val_obj, .as = .{
            .obj = obj,
        } };
    }
    pub inline fn isBool(self: *const Value) bool {
        return self.t == .val_bool;
    }
    pub inline fn isNumber(self: *const Value) bool {
        return self.t == .val_number;
    }
    pub inline fn isNil(self: *const Value) bool {
        return self.t == .val_nil;
    }
    pub inline fn isObject(self: *const Value) bool {
        return self.t == .val_obj;
    }
    pub inline fn isString(self: *const Value) bool {
        if (!self.isObject()) return false;
        return self.as.obj.t == .obj_string;
    }
};

pub fn printValue(v: Value, writer: anytype) void {
    switch (v.t) {
        .val_bool => (if (v.as.boolean) writer.print("true", .{}) else writer.print("false", .{})) catch unreachable,
        .val_nil => writer.print("nil", .{}) catch unreachable,
        .val_number => writer.print("{d}", .{v.as.number}) catch unreachable,
        .val_obj => v.as.obj.print(writer),
    }
}

pub fn valuesEqual(val1: Value, val2: Value) bool {
    if (val1.t != val2.t) return false;
    switch (val1.t) {
        .val_bool => return val1.as.boolean == val2.as.boolean,
        .val_nil => return true,
        .val_number => return val1.as.number == val2.as.number,
        .val_obj => return val1.as.obj == val2.as.obj,
    }
}

pub const ValueArray = struct {
    allocator: std.mem.Allocator,
    capacity: u32 = 0,
    count: u32 = 0,
    values: [*]Value = undefined,

    pub fn init(allocator: std.mem.Allocator) ValueArray {
        return .{
            .allocator = allocator,
        };
    }

    pub fn writeValueArray(self: *ValueArray, value: Value) void {
        if (self.capacity <= self.count) {
            const old_c = self.capacity;
            self.capacity = if (old_c < 8) 8 else old_c * 2;
            self.values = memory.growArray(Value, self.values, old_c, self.capacity, self.allocator);
        }
        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn freeValueArray(self: *ValueArray) void {
        memory.freeArray(Value, self.values, self.capacity, self.allocator);
        self.count = 0;
        self.capacity = 0;
        self.values = undefined;
    }
};
