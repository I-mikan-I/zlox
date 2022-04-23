const std = @import("std");
const memory = @import("./memory.zig");

pub const ValueType = enum {
    val_bool,
    val_nil,
    val_number,
};

pub const Value = struct {
    t: ValueType,
    as: union {
        boolean: bool,
        number: f64,
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
    pub inline fn IsBool(self: *const Value) bool {
        return self.t == .val_bool;
    }
    pub inline fn IsNumber(self: *const Value) bool {
        return self.t == .val_number;
    }
    pub inline fn IsNil(self: *const Value) bool {
        return self.t == .val_nil;
    }
};

pub fn printValue(v: Value, writer: anytype) void {
    switch (v.t) {
        .val_bool => (if (v.as.boolean) writer.print("true", .{}) else writer.print("false", .{})) catch unreachable,
        .val_nil => writer.print("nil", .{}) catch unreachable,
        .val_number => writer.print("{d}", .{v.as.number}) catch unreachable,
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
