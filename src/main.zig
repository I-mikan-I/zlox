const std = @import("std");
const chunk = @import("./chunk.zig");

pub fn main() anyerror!void {
    std.log.info("{x}", .{@enumToInt(chunk.OpCode.op_return)});
    std.log.info("{b}", .{@import("./common.zig").trace_enabled});
}

test "chunks" {
    const debug = @import("./debug.zig");
    const vm = @import("./vm.zig");
    const a = std.testing.allocator;
    var c = chunk.Chunk.init(a);
    var constant = c.addConstant(1.2);
    c.writeChunk(@enumToInt(chunk.OpCode.op_constant), 123);
    c.writeChunk(constant, 123);

    constant = c.addConstant(3.4);
    c.writeChunk(@enumToInt(chunk.OpCode.op_constant), 123);
    c.writeChunk(constant, 123);

    c.writeChunk(@enumToInt(chunk.OpCode.op_add), 123);

    constant = c.addConstant(5.6);
    c.writeChunk(@enumToInt(chunk.OpCode.op_constant), 123);
    c.writeChunk(constant, 123);

    c.writeChunk(@enumToInt(chunk.OpCode.op_divide), 123);
    c.writeChunk(@enumToInt(chunk.OpCode.op_negate), 123);
    c.writeChunk(@enumToInt(chunk.OpCode.op_return), 123);
    std.debug.print("\nDISASM\n", .{});
    debug.disassembleChunk(&c, "test chunk"[0..]);
    std.debug.print("\nEXEC\n", .{});
    _ = vm.interpret(&c);
    c.freeChunk();
}
