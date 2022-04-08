const std = @import("std");
const scanner = @import("./scanner.zig");

pub fn compile(source: []const u8) void {
    var s = scanner.Scanner.init(source);
    var line: isize = -1;
    while (true) {
        const token = s.scanToken();
        if (token.line != line) {
            std.log.info("{d:4} ", .{token});
            line = @intCast(isize, token.line);
        } else {
            std.log.info("   | ", .{});
        }
        std.log.info("{d:2} '{s}'\n", .{ @enumToInt(token.t), token.start[0..token.length] });
        if (token.t == .lox_eof) break;
    }
}
