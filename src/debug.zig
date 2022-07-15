const chunk = @import("./chunk.zig");
const std = @import("std");
const value = @import("./value.zig");
const common = @import("./common.zig");

const stdout = common.stdout;

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
    return switch (@intToEnum(chunk.OpCode, instruction)) {
        .op_return => simpleInstruction("OP_RETURN", offset),
        .op_constant => constantInstruction("OP_CONSTANT", c, offset),
        .op_not => simpleInstruction("OP_NOT", offset),
        .op_negate => simpleInstruction("OP_NEGATE", offset),
        .op_add => simpleInstruction("OP_ADD", offset),
        .op_subtract => simpleInstruction("OP_SUBTRACT", offset),
        .op_multiply => simpleInstruction("OP_MULTIPLY", offset),
        .op_divide => simpleInstruction("OP_DIVIDE", offset),
        .op_nil => simpleInstruction("OP_NIL", offset),
        .op_true => simpleInstruction("OP_TRUE", offset),
        .op_false => simpleInstruction("OP_FALSE", offset),
        .op_equal => simpleInstruction("OP_EQUAL", offset),
        .op_greater => simpleInstruction("OP_GREATER", offset),
        .op_less => simpleInstruction("OP_LESS", offset),
        .op_print => simpleInstruction("OP_PRINT", offset),
        .op_pop => simpleInstruction("OP_POP", offset),
        .op_define_global => constantInstruction("OP_DEFINE_GLOBAL", c, offset),
        .op_get_global => constantInstruction("OP_GET_GLOBAL", c, offset),
        .op_set_global => constantInstruction("OP_SET_GLOBAL", c, offset),
        .op_get_local => byteInstruction("OP_GET_LOCAL", c, offset),
        .op_set_local => byteInstruction("OP_SET_LOCAL", c, offset),
        .op_jump => jumpInstruction("OP_JUMP", 1, c, offset),
        .op_jump_if_false => jumpInstruction("OP_JUMP_IF_FALSE", 1, c, offset),
        .op_loop => jumpInstruction("OP_LOOP", -1, c, offset),
        .op_call => byteInstruction("OP_CALL", c, offset),
        .op_get_upvalue => byteInstruction("OP_GET_UPVALUE", c, offset),
        .op_set_upvalue => byteInstruction("OP_SET_UPVALUE", c, offset),
        .op_close_upvalue => simpleInstruction("OP_CLOSE_UPVALUE", offset),
        .op_closure => blk: {
            var offset_t = offset;
            offset_t += 1;
            const con = c.code[offset_t];
            offset_t += 1;
            stdout.print("{s:<16} {d:4} ", .{ "OP_CLOSURE", con }) catch unreachable;
            value.printValue(c.constants.values[con], stdout);
            stdout.print("\n", .{}) catch unreachable;
            const function = c.constants.values[con].as.obj.asFunction();
            var i: usize = 0;
            while (i < function.upvalue_count) : (i += 1) {
                const is_local = c.code[offset_t];
                offset_t += 1;
                const index = c.code[offset_t];
                offset_t += 1;
                const name: []const u8 = if (is_local == 1) "local" else "upvalue";
                stdout.print("{d:0>4}      |                     {s} {d}\n", .{ offset_t - 2, name, index }) catch unreachable;
            }
            break :blk offset_t;
        },
        .op_class => constantInstruction("OP_CLASS", c, offset),
        .op_get_property => constantInstruction("OP_GET_PROPERTY", c, offset),
        .op_set_property => constantInstruction("OP_SET_PROPERTY", c, offset),
        .op_method => constantInstruction("OP_METHOD", c, offset),
        .op_invoke => invokeInstruction("OP_INVOKE", c, offset),
        .op_inherit => simpleInstruction("OP_INHERIT", offset),
        .op_get_super => constantInstruction("OP_GET_SUPER", c, offset),
        .op_super_invoke => invokeInstruction("OP_SUPER_INVOKE", c, offset),
    };
}

fn simpleInstruction(name: []const u8, offset: u32) u32 {
    stdout.print("{s}\n", .{name}) catch unreachable;
    return offset + 1;
}

fn byteInstruction(name: []const u8, c: *chunk.Chunk, offset: u32) u32 {
    const slot = c.code[offset + 1];
    stdout.print("{s:<16} {d:4}\n", .{ name, slot }) catch unreachable;
    return offset + 2;
}

fn constantInstruction(name: []const u8, c: *chunk.Chunk, offset: u32) u32 {
    const index = c.code[offset + 1];
    stdout.print("{s:<16} {d:4} '", .{ name, index }) catch unreachable;
    value.printValue(c.constants.values[index], stdout);
    stdout.print("'\n", .{}) catch unreachable;
    return offset + 2;
}

fn jumpInstruction(name: []const u8, sign: isize, c: *chunk.Chunk, offset: u32) u32 {
    var jump: u16 = c.code[offset + 1];
    jump <<= 8;
    jump |= c.code[offset + 2];
    stdout.print("{s:<16} {d:4} -> {d}\n", .{ name, offset, offset + 3 + sign * jump }) catch unreachable;
    return offset + 3;
}

fn invokeInstruction(name: []const u8, c: *chunk.Chunk, offset: u32) u32 {
    const constant = c.code[offset + 1];
    const arg_count = c.code[offset + 2];
    stdout.print("{s:<16} ({d} args) {d:4} ", .{ name, arg_count, constant }) catch unreachable;
    value.printValue(c.constants.values[constant], stdout);
    stdout.print("\n", .{}) catch unreachable;
    return offset + 3;
}
