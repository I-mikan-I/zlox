const std = @import("std");
const stdout = std.io.getStdOut().writer();
const scanner = @import("./scanner.zig");

pub fn compile(source: [:0]const u8) void {
    var s = scanner.Scanner.init(source);
    var line: isize = -1;
    while (true) {
        const token = s.scanToken();
        if (token.line != line) {
            stdout.print("{d:4} ", .{token.line}) catch unreachable;
            line = @intCast(isize, token.line);
        } else {
            stdout.print("   | ", .{}) catch unreachable;
        }
        stdout.print("{s: <15} '{s}'\n", .{ @tagName(token.t), token.start[0..token.length] }) catch unreachable;
        if (token.t == .lox_eof) break;
    }
}
