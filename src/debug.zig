const chunk = @import("./chunk.zig");
const std = @import("std");
const stdout = std.io.getStdOut().writer();

pub fn disassembleChunk(c: *chunk.Chunk, name: []const u8) void {
    stdout.print("== {s} ==\n", .{name}) catch unreachable;
    var offset: u32 = 0;
    while (offset < c.count) {
        offset = disassembleInstruction(c, offset);
    }
}

pub fn disassembleInstruction(c: *chunk.Chunk, offset: u32) u32 {
    stdout.print("{d:04} ", .{offset}) catch unreachable;
    const instruction = c.code[offset];
    return switch (instruction) {
        @enumToInt(chunk.OpCode.op_return) => simpleInstruction("OP_RETURN", offset),
        else => blk: {
            stdout.print("Unknown opcode {d}\n", .{instruction}) catch unreachable;
            break :blk offset + 1;
        },
    };
}

fn simpleInstruction(name: []const u8, offset: u32) u32 {
    stdout.print("{s}\n", .{name}) catch unreachable;
    return offset + 1;
}
