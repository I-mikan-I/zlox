const chunk = @import("./chunk.zig");
const std = @import("std");
const value = @import("./value.zig");
const stdout = std.io.getStdOut().writer();

pub fn disassembleChunk(c: *chunk.Chunk, name: []const u8) void {
    stdout.print("== {s} ==\n", .{name}) catch unreachable;
    var offset: u32 = 0;
    while (offset < c.count) {
        offset = disassembleInstruction(c, offset);
    }
}

pub fn disassembleInstruction(c: *chunk.Chunk, offset: u32) u32 {
    stdout.print("{d:0>4} ", .{offset}) catch unreachable;
    if (offset > 0 and c.lines[offset] == c.lines[offset - 1]) {
        stdout.print("   | ", .{}) catch unreachable;
    } else {
        stdout.print("{d:4} ", .{c.lines[offset]}) catch unreachable;
    }
    const instruction = c.code[offset];
    return switch (instruction) {
        @enumToInt(chunk.OpCode.op_return) => simpleInstruction("OP_RETURN", offset),
        @enumToInt(chunk.OpCode.op_constant) => constantInstruction("OP_CONSTANT", c, offset),
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

fn constantInstruction(name: []const u8, c: *chunk.Chunk, offset: u32) u32 {
    const index = c.code[offset + 1];
    stdout.print("{s:<16} {d:4} '", .{ name, index }) catch unreachable;
    value.printValue(c.constants.values[index], stdout);
    stdout.print("'\n", .{}) catch unreachable;
    return offset + 2;
}
