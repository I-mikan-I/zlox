const std = @import("std");
const memory = @import("./memory.zig");

pub const OpCode = enum {
    op_return,
};

pub const Chunk = struct {
    allocator: std.mem.Allocator,
    count: u32 = 0,
    capacity: u32 = 0,
    code: [*]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return .{
            .allocator = allocator,
        };
    }

    pub fn writeChunk(self: *Chunk, byte: u8) void {
        if (self.capacity <= self.count) {
            const old_c = self.capacity;
            self.capacity = if (old_c < 8) 8 else old_c * 2;
            self.code = memory.growArray(u8, self.code, old_c, self.capacity);
        }
        self.code[self.count] = byte;
        self.count += 1;
    }
};
