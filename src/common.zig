const Value = @import("./value.zig").Value;
const std = @import("std");
const builtin = @import("builtin");
pub const alloc = if (builtin.mode == std.builtin.Mode.Debug) std.testing.allocator else std.heap.c_allocator;
pub const trace_enabled = @import("build_options").trace_enable;
pub const dump_enabled = @import("build_options").dump_code;

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
