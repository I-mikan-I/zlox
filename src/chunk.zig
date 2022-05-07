const std = @import("std");
const memory = @import("./memory.zig");
const common = @import("./common.zig");
const ValueArray = @import("./value.zig").ValueArray;
const Value = @import("./value.zig").Value;

pub const OpCode = enum(u8) {
    op_constant, // arg 1: constant index
    op_nil,
    op_true,
    op_false,
    op_pop,
    op_get_local,
    op_get_global,
    op_define_global,
    op_set_local,
    op_set_global,
    op_equal,
    op_greater,
    op_less,
    op_add,
    op_subtract,
    op_multiply,
    op_divide,
    op_not,
    op_negate,
    op_print,
    op_jump,
    op_jump_if_false,
    op_return,
};

pub const Chunk = struct {
    allocator: std.mem.Allocator,
    count: u32 = 0,
    capacity: u32 = 0,
    code: [*]u8 = undefined,
    constants: ValueArray,
    lines: [*]u32 = undefined,

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return .{
            .allocator = allocator,
            .constants = ValueArray.init(allocator),
        };
    }

    pub fn writeChunk(self: *Chunk, byte: u8, line: u32) void {
        if (self.capacity <= self.count) {
            const old_c = self.capacity;
            self.capacity = common.growCapacity(old_c);
            self.code = memory.growArray(u8, self.code, old_c, self.capacity, self.allocator);
            self.lines = memory.growArray(u32, self.lines, old_c, self.capacity, self.allocator);
        }
        self.code[self.count] = byte;
        self.lines[self.count] = line;
        self.count += 1;
    }

    pub fn addConstant(self: *Chunk, value: Value) u32 {
        self.constants.writeValueArray(value);
        return @intCast(u32, self.constants.count - 1);
    }

    pub fn freeChunk(self: *Chunk) void {
        memory.freeArray(u8, self.code, self.capacity, self.allocator);
        memory.freeArray(u32, self.lines, self.capacity, self.allocator);
        self.count = 0;
        self.capacity = 0;
        self.code = undefined;
        self.constants.freeValueArray();
    }
};
