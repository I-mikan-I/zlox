const std = @import("std");
const chunk = @import("./chunk.zig");

pub fn main() anyerror!void {
    std.log.info("{x}", .{@enumToInt(chunk.OpCode.op_return)});
}

test "chunks" {
    const debug = @import("./debug.zig");
    const a = std.testing.allocator;
    var c = chunk.Chunk.init(a);
    var constant = c.addConstant(1.2);
    c.writeChunk(@enumToInt(chunk.OpCode.op_constant), 123);
    c.writeChunk(constant, 123);

    c.writeChunk(@enumToInt(chunk.OpCode.op_return), 123);
    debug.disassembleChunk(&c, "test chunk"[0..]);
    c.freeChunk();
}
