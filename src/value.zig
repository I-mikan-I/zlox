const std = @import("std");
const memory = @import("./memory.zig");
const object = @import("./object.zig");
const common = @import("./common.zig");
const Obj = object.Obj;

pub const ValueType = enum {
    val_bool,
    val_nil,
    val_number,
    val_obj,
};

const ensureSize = blk: {
    if (common.nan_boxing) {
        if (@sizeOf(Value) > @sizeOf(u64)) {
            @compileError("Expected Value to be 8 byte large with NaN boxing.");
        }
    }
    break :blk undefined;
};

pub const Value = if (common.nan_boxing)
    struct {
        const QNAN = 0x7ffc << 48;
        const SIGN_BIT = 1 << 63;
        const TAG_NIL = 1;
        const TAG_FALSE = 2;
        const TAG_TRUE = 3;
        v: u64,
        pub inline fn Boolean(value: bool) Value {
            const tag: u64 = if (value) TAG_TRUE else TAG_FALSE;
            return .{ .v = QNAN | tag };
        }
        pub inline fn Nil() Value {
            return .{ .v = QNAN | TAG_NIL };
        }
        pub inline fn Number(value: f64) Value {
            return .{ .v = @bitCast(u64, value) };
        }
        pub inline fn Object(obj: *Obj) Value {
            return .{ .v = SIGN_BIT | QNAN | @ptrToInt(obj) };
        }

        pub inline fn asBoolean(self: *const Value) bool {
            return self.v == QNAN | TAG_TRUE;
        }
        pub inline fn asObject(self: *const Value) *Obj {
            return @intToPtr(*Obj, self.v & ~(@intCast(u64, (SIGN_BIT | QNAN))));
        }
        pub inline fn asNumber(self: *const Value) f64 {
            return @bitCast(f64, self.v);
        }

        pub inline fn isBool(self: *const Value) bool {
            return self.v | 1 == QNAN | TAG_TRUE;
        }
        pub inline fn isNumber(self: *const Value) bool {
            return self.v & QNAN != QNAN;
        }
        pub inline fn isNil(self: *const Value) bool {
            return self.v == QNAN | TAG_NIL;
        }
        pub inline fn isObject(self: *const Value) bool {
            return self.v & (QNAN | SIGN_BIT) == (QNAN | SIGN_BIT);
        }
        pub inline fn isString(self: *const Value) bool {
            if (!self.isObject()) return false;
            return self.asObject().t == .obj_string;
        }
        pub inline fn isFunction(self: *const Value) bool {
            if (!self.isObject()) return false;
            return self.asObject().t == .obj_function;
        }
        pub inline fn isClass(self: *const Value) bool {
            if (!self.isObject()) return false;
            return self.asObject().t == .obj_class;
        }
        pub inline fn isInstance(self: *const Value) bool {
            if (!self.isObject()) return false;
            return self.asObject().t == .obj_instance;
        }
        pub inline fn isBoundMethod(self: *const Value) bool {
            if (!self.isObject()) return false;
            return self.asObject().t == .obj_bound_method;
        }
    }
else
    struct {
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

        pub inline fn asBoolean(self: *const Value) bool {
            return self.as.boolean;
        }
        pub inline fn asObject(self: *const Value) *Obj {
            return self.as.obj;
        }
        pub inline fn asNumber(self: *const Value) f64 {
            return self.as.number;
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
            return self.asObject().t == .obj_string;
        }
        pub inline fn isFunction(self: *const Value) bool {
            if (!self.isObject()) return false;
            return self.asObject().t == .obj_function;
        }
        pub inline fn isClass(self: *const Value) bool {
            if (!self.isObject()) return false;
            return self.asObject().t == .obj_class;
        }
        pub inline fn isInstance(self: *const Value) bool {
            if (!self.isObject()) return false;
            return self.asObject().t == .obj_instance;
        }
        pub inline fn isBoundMethod(self: *const Value) bool {
            if (!self.isObject()) return false;
            return self.asObject().t == .obj_bound_method;
        }
    };

pub fn printValue(v: Value, writer: anytype) void {
    if (common.nan_boxing) {
        if (v.isBool()) {
            (if (v.asBoolean()) writer.print("true", .{}) else writer.print("false", .{})) catch unreachable;
        }
        if (v.isNil()) {
            writer.print("nil", .{}) catch unreachable;
        }
        if (v.isNumber()) {
            writer.print("{d}", .{v.asNumber()}) catch unreachable;
        }
        if (v.isObject()) {
            v.asObject().print(writer);
        }
    } else {
        switch (v.t) {
            .val_bool => (if (v.asBoolean()) writer.print("true", .{}) else writer.print("false", .{})) catch unreachable,
            .val_nil => writer.print("nil", .{}) catch unreachable,
            .val_number => writer.print("{d}", .{v.as.number}) catch unreachable,
            .val_obj => v.as.obj.print(writer),
        }
    }
}

pub fn valuesEqual(val1: Value, val2: Value) bool {
    if (common.nan_boxing) {
        if (val1.isNumber() and val2.isNumber()) {
            return val1.asNumber() == val2.asNumber();
        }
        return val1.v == val2.v;
    } else {
        if (val1.t != val2.t) return false;
        switch (val1.t) {
            .val_bool => return val1.asBoolean() == val2.asBoolean(),
            .val_nil => return true,
            .val_number => return val1.asNumber() == val2.asNumber(),
            .val_obj => return val1.asObject() == val2.asObject(),
        }
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
            self.values = memory.growArray(Value, self.values, old_c, self.capacity);
        }
        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn freeValueArray(self: *ValueArray) void {
        memory.freeArray(Value, self.values, self.capacity);
        self.count = 0;
        self.capacity = 0;
        self.values = undefined;
    }
};

test "refAllDecls" {
    const file = @import("./value.zig");
    std.testing.refAllDecls(file);
}
