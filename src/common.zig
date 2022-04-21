pub const trace_enabled = @import("build_options").trace_enable;
pub const dump_enabled = @import("build_options").dump_code;

pub fn add(a: anytype, b: anytype) @TypeOf(a) {
    return a + b;
}

pub fn sub(a: anytype, b: anytype) @TypeOf(a) {
    return a - b;
}

pub fn mul(a: anytype, b: anytype) @TypeOf(a) {
    return a * b;
}

pub fn div(a: anytype, b: anytype) @TypeOf(a) {
    return a / b;
}
