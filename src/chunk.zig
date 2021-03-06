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
    op_get_upvalue,
    op_define_global,
    op_set_local,
    op_set_global,
    op_set_upvalue,
    op_get_property,
    op_set_property,
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
    op_loop,
    op_call,
    op_invoke,
    op_super_invoke,
    op_closure,
    op_close_upvalue,
    op_return,
    op_class,
    op_inherit,
    op_get_super,
    op_method,
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
            self.code = memory.growArray(u8, self.code, old_c, self.capacity);
            self.lines = memory.growArray(u32, self.lines, old_c, self.capacity);
        }
        self.code[self.count] = byte;
        self.lines[self.count] = line;
        self.count += 1;
    }

    pub fn addConstant(self: *Chunk, value: Value) u32 {
        memory.vm.push(value);
        self.constants.writeValueArray(value);
        _ = memory.vm.pop();
        return @intCast(u32, self.constants.count - 1);
    }

    pub fn freeChunk(self: *Chunk) void {
        memory.freeArray(u8, self.code, self.capacity);
        memory.freeArray(u32, self.lines, self.capacity);
        self.count = 0;
        self.capacity = 0;
        self.code = undefined;
        self.constants.freeValueArray();
    }
};
