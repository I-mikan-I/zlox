const std = @import("std");
const memory = @import("./memory.zig");
pub const Value = f64;

pub fn printValue(v: Value, writer: anytype) void {
    writer.print("{d}", .{v}) catch unreachable;
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
            self.code = memory.growArray(Value, self.code, old_c, self.capacity, self.allocator);
        }
        self.code[self.count] = value;
        self.count += 1;
    }

    pub fn freeValueArray(self: *ValueArray) void {
        memory.freeArray(Value, self.values, self.capacity, self.allocator);
        self.count = 0;
        self.capacity = 0;
        self.values = undefined;
    }
};
