const std = @import("std");
const chunk = @import("./chunk.zig");
const debug = @import("./debug.zig");
const compiler = @import("./compiler.zig");
const memory = @import("./memory.zig");
const object = @import("./object.zig");
const value = @import("./value.zig");
const common = @import("./common.zig");
const Table = @import("./table.zig").Table;
const Chunk = chunk.Chunk;
const Value = value.Value;
const Obj = object.Obj;
const ObjFunction = object.ObjFunction;
const ObjClosure = object.ObjClosure;
const ObjNative = object.ObjNative;
const ObjUpvalue = object.ObjUpvalue;

const alloc = common.alloc;
var stdout = common.stdout;
var stderr = common.stderr;

fn clockNative(_: usize, _: [*]Value) Value {
    var ts = std.os.timespec{ .tv_sec = 0, .tv_nsec = 0 };
    std.os.clock_gettime(std.os.CLOCK.MONOTONIC, &ts) catch std.os.exit(1);
    return Value.Number(@intToFloat(f64, ts.tv_sec) + @intToFloat(f64, ts.tv_nsec) / 1_000_000_000.0);
}

const CallFrame = struct {
    closure: *ObjClosure,
    ip: [*]u8,
    slots: [*]Value,
};

pub const VM = struct {
    const frames_max = 64;
    const stack_max = frames_max * 256;
    pub var objects: ?*object.Obj = null; // linked list of allocated objects
    pub var strings: Table = undefined;
    init_string: ?*object.ObjString = null,
    bytes_allocated: isize = undefined,
    next_gc: isize = undefined,
    gray_count: usize = 0,
    gray_stack: []*Obj = &.{},
    frames: [frames_max]CallFrame = undefined,
    open_upvalues: ?*ObjUpvalue = null,
    frame_count: usize = 0,
    frame: *CallFrame = undefined,
    globals: Table = undefined,
    stack: *[stack_max]Value = undefined,
    chunk: *Chunk = undefined,
    stack_top: [*]Value = undefined,

    pub fn initVM(self: *VM) void {
        var vm = self;
        vm.bytes_allocated = 0;
        vm.next_gc = 1024 * 1024;
        memory.initGC(vm);
        vm.globals = Table.initTable();
        vm.stack = alloc.create([stack_max]Value) catch std.os.exit(1);
        vm.resetStack();
        strings = Table.initTable();
        vm.defineNative("clock", clockNative);
        vm.init_string = object.copyString("init", 4).asString();
    }

    pub fn freeVM(self: *VM) void {
        strings.freeTable();
        self.globals.freeTable();
        memory.freeObjects();
        alloc.destroy(self.stack);
        alloc.free(self.gray_stack);
        self.gray_count = 0;
        self.gray_stack = &.{};
        self.open_upvalues = null;
        self.frame_count = 0;
        objects = null;
        self.init_string = null;
    }

    pub fn interpret(self: *VM, source: [:0]const u8) InterpretResult {
        const function = compiler.compile(source) orelse return .interpret_compile_error;
        self.push(Value.Object(@ptrCast(*Obj, function)));
        const closure = object.newClosure(function);
        _ = self.pop();
        self.push(Value.Object(@ptrCast(*Obj, closure)));
        _ = self.call(closure, 0);

        return self.run();
    }

    fn run(self: *VM) InterpretResult {
        self.frame = &self.frames[self.frame_count - 1];
        while (true) {
            if (common.trace_enabled) {
                stdout.print("          ", .{}) catch unreachable;
                for (self.stack) |*v| {
                    if (@ptrToInt(v) >= @ptrToInt(self.stack_top)) {
                        break;
                    }
                    stdout.print("[ ", .{}) catch unreachable;
                    value.printValue(v.*, stdout);
                    stdout.print(" ]", .{}) catch unreachable;
                }
                stdout.print("\n", .{}) catch unreachable;
                _ = debug.disassembleInstruction(self.frame.closure.function.chunk(), @intCast(u32, @ptrToInt(self.frame.ip) - @ptrToInt(self.frame.closure.function.chunk().code)));
            }
            const inst = @intToEnum(chunk.OpCode, self.readByte());
            switch (inst) {
                .op_return => {
                    const result = self.pop();
                    self.closeUpvalues(&self.frame.slots[0]);
                    self.frame_count -= 1;
                    if (self.frame_count == 0) {
                        _ = self.pop();
                        return .interpret_ok;
                    }

                    self.stack_top = self.frame.slots;
                    self.push(result);
                    self.frame = &self.frames[self.frame_count - 1];
                },
                .op_closure => {
                    const function = self.readConstant().asObject().asFunction();
                    const closure = object.newClosure(function);
                    self.push(Value.Object(@ptrCast(*Obj, closure)));
                    var i: usize = 0;
                    while (i < closure.upvalue_count) : (i += 1) {
                        const is_local = self.readByte();
                        const index = self.readByte();
                        if (is_local == 1) {
                            closure.upvalues[i] = self.captureUpvalue(&(self.frame.slots + index)[0]);
                        } else {
                            closure.upvalues[i] = self.frame.closure.upvalues[index];
                        }
                    }
                },
                .op_close_upvalue => {
                    self.closeUpvalues(&(self.stack_top - 1)[0]);
                    _ = self.pop();
                },
                .op_call => {
                    const arg_count = self.readByte();
                    if (!self.callValue(self.peek(arg_count), arg_count)) {
                        return .interpret_runtime_error;
                    }
                    self.frame = &self.frames[self.frame_count - 1];
                },
                .op_invoke => {
                    const method = self.readString();
                    const arg_count = self.readByte();
                    if (!self.invoke(method, arg_count)) {
                        return .interpret_runtime_error;
                    }
                    self.frame = &self.frames[self.frame_count - 1];
                },
                .op_super_invoke => {
                    const method = self.readString();
                    const arg_count = self.readByte();
                    const super = self.pop().asObject().asClass();
                    if (!self.invokeFromClass(super, method, arg_count)) {
                        return .interpret_runtime_error;
                    }
                    self.frame = &self.frames[self.frame_count - 1];
                },
                .op_get_super => {
                    const name = self.readString();
                    const super = self.pop().asObject().asClass();

                    if (!self.bindMethod(super, name)) {
                        return .interpret_runtime_error;
                    }
                },
                .op_jump => {
                    const offset = self.readShort();
                    self.frame.ip += offset;
                },
                .op_loop => {
                    const offset = self.readShort();
                    self.frame.ip -= offset;
                },
                .op_jump_if_false => {
                    const offset = self.readShort();
                    if (isFalsey(self.peek(0))) self.frame.ip += offset;
                },
                .op_constant => {
                    const constant = self.readConstant();
                    self.push(constant);
                },
                .op_nil => self.push(Value.Nil()),
                .op_true => self.push(Value.Boolean(true)),
                .op_false => self.push(Value.Boolean(false)),
                .op_equal => {
                    var a = self.pop();
                    var b = self.pop();
                    self.push(Value.Boolean(value.valuesEqual(a, b)));
                },
                .op_negate => {
                    if (!self.peek(0).isNumber()) {
                        self.runtimeError("Operand must be a number", .{});
                        return .interpret_runtime_error;
                    }
                    self.push(Value.Number(-(self.pop().asNumber())));
                },
                .op_print => {
                    value.printValue(self.pop(), stdout);
                    stdout.print("\n", .{}) catch unreachable;
                },
                .op_pop => {
                    _ = self.pop();
                },
                .op_get_local => {
                    const slot = self.readByte();
                    self.push(self.frame.slots[slot]);
                },
                .op_get_global => {
                    const name = self.readString();
                    if (self.globals.tableGet(name)) |v| {
                        self.push(v);
                    } else {
                        self.runtimeError("Undefined variable '{s}'", .{name.chars[0..name.length]});
                        return .interpret_runtime_error;
                    }
                },
                .op_get_upvalue => {
                    const slot = self.readByte();
                    self.push(self.frame.closure.upvalues[slot].?.location.*);
                },
                .op_define_global => {
                    const name = self.readString();
                    _ = self.globals.tableSet(name, self.peek(0));
                    _ = self.pop();
                },
                .op_set_local => {
                    const slot = self.readByte();
                    self.frame.slots[slot] = self.peek(0);
                },
                .op_set_global => {
                    const name = self.readString();
                    if (self.globals.tableSet(name, self.peek(0))) {
                        _ = self.globals.tableDelete(name);
                        self.runtimeError("Undefined variable '{s}'", .{name.chars[0..name.length]});
                        return .interpret_runtime_error;
                    }
                },
                .op_set_upvalue => {
                    const slot = self.readByte();
                    self.frame.closure.upvalues[slot].?.location.* = self.peek(0);
                },
                .op_greater => self.binary_op(common.greater) orelse return .interpret_runtime_error,
                .op_less => self.binary_op(common.less) orelse return .interpret_runtime_error,
                .op_add => {
                    const a = self.peek(0);
                    const b = self.peek(1);
                    if (a.isString() and b.isString()) self.concatenate() else if (a.isNumber() and b.isNumber()) {
                        _ = self.pop();
                        _ = self.pop();
                        self.push(Value.Number(a.asNumber() + b.asNumber()));
                    } else {
                        self.runtimeError("Operand must be two numbers or two strings.", .{});
                        return .interpret_runtime_error;
                    }
                },
                .op_subtract => self.binary_op(common.sub) orelse return .interpret_runtime_error,
                .op_multiply => self.binary_op(common.mul) orelse return .interpret_runtime_error,
                .op_divide => self.binary_op(common.div) orelse return .interpret_runtime_error,
                .op_not => self.push(Value.Boolean(isFalsey(self.pop()))),
                .op_class => {
                    self.push(Value.Object(object.newClass(self.readString())));
                },
                .op_inherit => {
                    const super = self.peek(1);
                    if (!super.isClass()) {
                        self.runtimeError("Superclass must be a class.", .{});
                        return .interpret_runtime_error;
                    }
                    const sub = self.peek(0).asObject().asClass();
                    sub.methods().tableAddAll(super.asObject().asClass().methods());
                    _ = self.pop();
                },
                .op_method => {
                    self.defineMethod(self.readString());
                },
                .op_get_property => {
                    if (!self.peek(0).isInstance()) {
                        self.runtimeError("Only instances have properties.", .{});
                        return .interpret_runtime_error;
                    }
                    const instance = self.peek(0).asObject().asInstance();
                    const name = self.readString();

                    if (instance.fields().tableGet(name)) |v| {
                        _ = self.pop();
                        self.push(v);
                    } else if (!self.bindMethod(instance.class, name)) {
                        return .interpret_runtime_error;
                    }
                },
                .op_set_property => {
                    if (!self.peek(1).isInstance()) {
                        self.runtimeError("Only instances have properties.", .{});
                        return .interpret_runtime_error;
                    }
                    const instance = self.peek(1).asObject().asInstance();
                    _ = instance.fields().tableSet(self.readString(), self.peek(0));
                    const v = self.pop();
                    _ = self.pop();
                    self.push(v);
                },
            }
        }
    }

    pub fn push(self: *VM, val: Value) void {
        std.debug.assert(@ptrToInt(self.stack_top) - @ptrToInt(self.stack) < stack_max);
        self.stack_top.* = val;
        self.stack_top += 1;
    }

    pub fn pop(self: *VM) Value {
        std.debug.assert(@ptrToInt(self.stack_top) - @ptrToInt(self.stack) > 0);
        self.stack_top -= 1;
        return self.stack_top[0];
    }

    fn callValue(self: *VM, callee: Value, arg_count: usize) bool {
        if (callee.isObject()) {
            switch (callee.asObject().t) {
                .obj_closure => {
                    return self.call(callee.asObject().asClosure(), arg_count);
                },
                .obj_native => {
                    const native = callee.asObject().asNative().function().*;
                    const result = native(arg_count, self.stack_top - arg_count);
                    self.stack_top -= arg_count + 1;
                    self.push(result);
                    return true;
                },
                .obj_class => {
                    const class = callee.asObject().asClass();
                    (self.stack_top - arg_count - 1)[0] = Value.Object(object.newInstance(class));
                    if (class.methods().tableGet(self.init_string.?)) |init| {
                        return self.call(init.asObject().asClosure(), arg_count);
                    } else if (arg_count > 0) {
                        self.runtimeError("Expected 0 arguments but got {d}.", .{arg_count});
                        return false;
                    }
                    return true;
                },
                .obj_bound_method => {
                    const bound = callee.asObject().asBoundMethod();
                    (self.stack_top - arg_count - 1)[0] = bound.receiver().*;
                    return self.call(bound.method, arg_count);
                },
                else => {},
            }
        }
        self.runtimeError("Can only call functions and classes.", .{});
        return false;
    }

    fn invoke(self: *VM, name: *object.ObjString, arg_count: u8) bool {
        const receiver = self.peek(arg_count);
        if (!receiver.isInstance()) {
            self.runtimeError("Only instances have methods.", .{});
            return false;
        }
        const instance = receiver.asObject().asInstance();
        if (instance.fields().tableGet(name)) |field| {
            (self.stack_top - arg_count - 1)[0] = field;
            return self.callValue(field, arg_count);
        }
        return self.invokeFromClass(instance.class, name, arg_count);
    }

    fn invokeFromClass(self: *VM, klass: *object.ObjClass, name: *object.ObjString, arg_count: u8) bool {
        if (klass.methods().tableGet(name)) |method| {
            return self.call(method.asObject().asClosure(), arg_count);
        } else {
            self.runtimeError("Undefined property '{s}'.", .{name.chars[0..name.length]});
            return false;
        }
    }

    fn bindMethod(self: *VM, klass: *object.ObjClass, name: *object.ObjString) bool {
        var method: ?Value = klass.methods().tableGet(name);
        if (method) |m| {
            const bound = object.newBoundMethod(self.peek(0), m.asObject().asClosure());
            _ = self.pop();
            self.push(Value.Object(bound));
            return true;
        } else {
            self.runtimeError("Undefined property '{s}'.", .{name.chars[0..name.length]});
            return false;
        }
    }

    fn captureUpvalue(self: *VM, local: *Value) *ObjUpvalue {
        var prev_upvalue: ?*ObjUpvalue = null;
        var upvalue = self.open_upvalues;
        while (upvalue != null and @ptrToInt(upvalue.?.location) > @ptrToInt(local)) {
            prev_upvalue = upvalue;
            upvalue = upvalue.?.next;
        }
        if (upvalue != null and upvalue.?.location == local) {
            return upvalue.?;
        }
        const created_upvalue = object.newUpvalue(local);
        created_upvalue.next = upvalue;
        if (prev_upvalue) |prev| {
            prev.next = created_upvalue;
        } else {
            self.open_upvalues = created_upvalue;
        }
        return created_upvalue;
    }

    fn closeUpvalues(self: *VM, last: *Value) void {
        while (self.open_upvalues != null and @ptrToInt(self.open_upvalues.?.location) >= @ptrToInt(last)) {
            const upvalue = self.open_upvalues.?;
            upvalue.closed().* = upvalue.location.*;
            upvalue.location = upvalue.closed();
            self.open_upvalues = self.open_upvalues.?.next;
        }
    }

    fn defineMethod(self: *VM, name: *object.ObjString) void {
        const method = self.peek(0);
        const klass = self.peek(1).asObject().asClass();
        _ = klass.methods().tableSet(name, method);
        _ = self.pop();
    }

    fn call(self: *VM, callee: *ObjClosure, arg_count: usize) bool {
        if (arg_count != callee.function.arity) {
            self.runtimeError("Expected {d} arguments but got {d}.", .{ callee.function.arity, arg_count });
            return false;
        }
        if (self.frame_count == frames_max) {
            self.runtimeError("Stack overflow.", .{});
            return false;
        }
        var frame = &self.frames[self.frame_count];
        self.frame_count += 1;
        frame.closure = callee;
        frame.ip = callee.function.chunk().code;
        frame.slots = self.stack_top - arg_count - 1;
        return true;
    }

    fn resetStack(self: *VM) void {
        self.stack_top = self.stack;
    }

    fn runtimeError(self: *VM, comptime format: []const u8, args: anytype) void {
        stderr.print(format, args) catch unreachable;
        stderr.writeByte('\n') catch unreachable;
        var index: isize = @intCast(isize, self.frame_count) - 1;
        while (index >= 0) : (index -= 1) {
            const frame = &self.frames[@intCast(usize, index)];
            const function = frame.closure.function;
            const instruction = @ptrToInt(frame.ip) - @ptrToInt(function.chunk().code) - 1;
            stderr.print("[line {d}] in ", .{function.chunk().lines[instruction]}) catch unreachable;
            if (function.name) |name| {
                stderr.print("{s}()\n", .{name.chars[0..name.length]}) catch unreachable;
            } else {
                stderr.print("script\n", .{}) catch unreachable;
            }
        }
        self.resetStack();
    }

    fn defineNative(self: *VM, name: []const u8, function: object.NativeFn) void {
        self.push(Value.Object(object.copyString(name.ptr, name.len)));
        self.push(Value.Object(object.newNative(function)));
        _ = self.globals.tableSet(self.stack[0].asObject().asString(), self.stack[1]);
        _ = self.pop();
        _ = self.pop();
    }

    fn peek(self: *VM, distance: usize) Value {
        return (self.stack_top - 1 - distance)[0];
    }

    fn isFalsey(val: Value) bool {
        return val.isNil() or (val.isBool() and !val.asBoolean());
    }

    fn concatenate(self: *VM) void {
        const b = self.peek(0).asObject().asString();
        const a = self.peek(1).asObject().asString();
        const length = a.length + b.length;
        const chars = memory.allocate(u8, length + 1);
        std.mem.copy(u8, chars[0..a.length], a.chars[0..a.length]);
        std.mem.copy(u8, chars[a.length..length], b.chars[0..b.length]);
        chars[length] = 0;
        const result = object.takeString(chars, length);
        _ = self.pop();
        _ = self.pop();
        self.push(Value.Object(result));
    }

    inline fn readByte(self: *VM) u8 {
        defer self.frame.ip += 1;
        return self.frame.ip[0];
    }

    inline fn readConstant(self: *VM) Value {
        return self.frame.closure.function.chunk().constants.values[self.readByte()];
    }

    inline fn readString(self: *VM) *object.ObjString {
        return self.readConstant().asObject().asString();
    }

    inline fn binary_op(self: *VM, comptime op: fn (f64, f64) Value) ?void {
        if (!self.peek(0).isNumber() or !self.peek(1).isNumber()) {
            self.runtimeError("Operands must be numbers.", .{});
            return null;
        }
        const b = self.pop().asNumber();
        const a = self.pop().asNumber();
        self.push(op(a, b));
        return;
    }

    inline fn readShort(self: *VM) u16 {
        self.frame.ip += 2;
        return (@intCast(u16, (self.frame.ip - 2)[0]) << 8) | (self.frame.ip - 1)[0];
    }
};

pub const InterpretResult = enum {
    interpret_ok,
    interpret_compile_error,
    interpret_runtime_error,
};
