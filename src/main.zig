const std = @import("std");
const chunk = @import("./chunk.zig");

pub fn main() anyerror!void {
    std.log.info("{x}", .{@enumToInt(chunk.OpCode.op_return)});
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
