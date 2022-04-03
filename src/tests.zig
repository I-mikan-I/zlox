const main = @import("./main.zig");
const std = @import("std");

test {
    std.testing.refAllDecls(@This());
}
