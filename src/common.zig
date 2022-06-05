const Value = @import("./value.zig").Value;
const std = @import("std");
const builtin = @import("builtin");
pub const alloc = if (builtin.mode == std.builtin.Mode.Debug) std.testing.allocator else std.heap.c_allocator;
pub const trace_enabled = @import("build_options").trace_enable;
pub const dump_enabled = @import("build_options").dump_code;
pub const stress_gc = @import("build_options").stress_gc;
pub const log_gc = @import("build_options").log_gc;
pub const gc_heap_growth_factor = 2;
pub const stdout = if (builtin.is_test) buffer_stream.writer() else std.io.getStdOut().writer();
pub const stderr = std.io.getStdErr().writer();

pub var buffer: if (builtin.is_test) [1 << 10 << 10]u8 else [0]u8 = if (builtin.is_test) .{0} ** (1 << 10 << 10) else .{};
pub var buffer_stream = if (builtin.is_test) std.io.fixedBufferStream(buffer[0..]) else @compileError("only used for testing");

pub fn add(a: f64, b: f64) Value {
    return Value.Number(a + b);
}

pub fn sub(a: f64, b: f64) Value {
    return Value.Number(a - b);
}

pub fn mul(a: f64, b: f64) Value {
    return Value.Number(a * b);
}

pub fn div(a: f64, b: f64) Value {
    return Value.Number(a / b);
}

pub fn greater(a: f64, b: f64) Value {
    return Value.Boolean(a > b);
}

pub fn less(a: f64, b: f64) Value {
    return Value.Boolean(a < b);
}

pub inline fn growCapacity(old_c: anytype) @TypeOf(old_c) {
    return if (old_c < 8) 8 else old_c * 2;
}
