const std = @import("std");
const object = @import("./object.zig");
const compiler = @import("./compiler.zig");
const common = @import("./common.zig");
const value = @import("./value.zig");
const VM = @import("./vm.zig").VM;
const Value = value.Value;
const ValueArray = value.ValueArray;
const Obj = object.Obj;
const ObjString = object.ObjString;
const ObjFunction = object.ObjFunction;
const ObjNative = object.ObjNative;
const ObjClosure = object.ObjClosure;
const ObjUpvalue = object.ObjUpvalue;
const ObjClass = object.ObjClass;
const ObjInstance = object.ObjInstance;

// TODO remove alloc parameters
const alloc: std.mem.Allocator = common.alloc;

pub var vm: *VM = undefined;

pub fn initGC(_vm: *VM) void {
    vm = _vm;
    object.initGC(_vm);
}

pub fn growArray(comptime t: type, ptr: [*]t, old_cap: u32, new_cap: u32) [*]t {
    return reallocate(ptr, old_cap, new_cap) orelse ptr;
}

pub fn freeArray(comptime t: type, ptr: [*]t, old_count: usize) void {
    _ = reallocate(ptr, old_count, 0);
    return;
}

fn free(comptime t: type, ptr: *t) void {
    _ = reallocate(@ptrCast([*]t, ptr), 1, 0);
    return;
}

pub fn allocate(comptime t: type, count: usize) [*]t {
    if (count < 1) return undefined;
    var tmp: [*]t = undefined;
    return reallocate(tmp, 0, count).?;
}

pub fn reallocate(pointer: anytype, old_size: usize, new_size: usize) ?@TypeOf(pointer) {
    const info = @typeInfo(@TypeOf(pointer));
    if (info != .Pointer) {
        unreachable;
    }
    vm.bytes_allocated += @intCast(isize, new_size) - @intCast(isize, old_size);
    if (comptime common.stress_gc) {
        if (new_size > old_size) {
            collectGarbage();
        }
    }
    if (vm.bytes_allocated > vm.next_gc) {
        collectGarbage();
    }
    if (new_size == 0) {
        alloc.free(pointer[0..old_size]);
        return null;
    }
    if (old_size == 0) {
        return (alloc.alloc(info.Pointer.child, new_size) catch std.os.exit(1)).ptr;
    }
    return (alloc.realloc(pointer[0..old_size], new_size) catch std.os.exit(1)).ptr;
}

pub fn freeObjects() void {
    var obj = VM.objects;
    while (obj) |o| {
        const next = o.next;
        freeObject(o);
        obj = next;
    }
    VM.objects = null;
}

fn freeObject(o: *Obj) void {
    if (comptime common.log_gc) {
        const stdout = common.stdout;
        stdout.print("{*} free type {any}\n", .{ o, o.t }) catch unreachable;
    }

    switch (o.t) {
        .obj_string => {
            const str = o.asString();
            freeArray(u8, str.chars, str.length + 1);
            free(ObjString, str);
        },
        .obj_function => {
            const function = o.asFunction();
            function.chunk().freeChunk();
            free(ObjFunction, function);
        },
        .obj_native => {
            free(ObjNative, o.asNative());
        },
        .obj_closure => {
            const closure = o.asClosure();
            freeArray(?*ObjUpvalue, closure.upvalues, closure.upvalue_count);
            free(ObjClosure, o.asClosure());
        },
        .obj_upvalue => {
            free(ObjUpvalue, o.asUpvalue());
        },
        .obj_class => {
            free(ObjClass, o.asClass());
        },
        .obj_instance => {
            const instance = o.asInstance();
            instance.fields().freeTable();
            free(ObjInstance, instance);
        },
    }
}

fn collectGarbage() void {
    if (comptime common.log_gc) {
        const stdout = common.stdout;
        stdout.print("-- gc begin\n", .{}) catch unreachable;
    }
    const before = vm.bytes_allocated;

    markRoots();
    traceReferences();
    VM.strings.removeWhite();
    sweep();
    vm.next_gc = vm.bytes_allocated * common.gc_heap_growth_factor;

    if (comptime common.log_gc) {
        const stdout = common.stdout;
        stdout.print("-- gc end\n", .{}) catch unreachable;
        stdout.print("   collected {d} bytes (from {d} to {d}) next at {d}\n", .{ before - vm.bytes_allocated, before, vm.bytes_allocated, vm.next_gc }) catch unreachable;
    }
}

fn markRoots() void {
    for (vm.stack) |*slot| {
        markValue(slot);
    }
    for (vm.frames[0..vm.frame_count]) |frame| {
        markObject(@ptrCast(*Obj, frame.closure));
    }
    var up_value = vm.open_upvalues;
    while (up_value) |uval| : (up_value = uval.next) {
        markObject(@ptrCast(*Obj, uval));
    }
    vm.globals.markTable();
    compiler.markCompilerRoots();
}

fn traceReferences() void {
    while (vm.gray_count > 0) {
        vm.gray_count -= 1;
        var obj = vm.gray_stack[vm.gray_count];
        blackenObject(obj);
    }
}

fn sweep() void {
    var previous: ?*Obj = null;
    var obj = VM.objects;
    while (obj) |o| {
        if (o.is_marked) {
            o.is_marked = false;
            previous = obj;
            obj = o.next;
        } else {
            var unreached = o;
            obj = o.next;
            if (previous) |p| {
                p.next = obj;
            } else {
                VM.objects = obj;
            }

            freeObject(unreached);
        }
    }
}

pub fn blackenObject(obj: *Obj) void {
    if (comptime common.log_gc) {
        const stdout = common.stdout;
        stdout.print("{*} blacken ", .{obj}) catch unreachable;
        value.printValue(Value.Object(obj), stdout);
        stdout.print("\n", .{}) catch unreachable;
    }
    switch (obj.t) {
        .obj_upvalue => {
            markValue(obj.asUpvalue().closed());
        },
        .obj_function => {
            var function = obj.asFunction();
            markObject(@ptrCast(?*Obj, function.name));
            markArray(&function.chunk().constants);
        },
        .obj_closure => {
            var closure = obj.asClosure();
            markObject(@ptrCast(*Obj, closure.function));
            for (closure.upvalues[0..closure.upvalue_count]) |uv| {
                markObject(@ptrCast(?*Obj, uv));
            }
        },
        .obj_instance => {
            var instance = obj.asInstance();
            markObject(@ptrCast(*Obj, instance.class));
            instance.fields().markTable();
        },
        .obj_class => {
            const class = obj.asClass();
            markObject(@ptrCast(*Obj, class.name));
        },
        .obj_native, .obj_string => {},
    }
}

pub fn markValue(slot: *Value) void {
    if (slot.isObject()) {
        markObject(slot.as.obj);
    }
}

pub fn markArray(array: *ValueArray) void {
    for (array.values[0..array.count]) |*val| {
        markValue(val);
    }
}

pub fn markObject(obj: ?*Obj) void {
    if (obj) |o| {
        if (o.is_marked) return;
        if (comptime common.log_gc) {
            const stdout = common.stdout;
            stdout.print("{*} mark ", .{o}) catch unreachable;
            value.printValue(Value.Object(o), stdout);
            stdout.print("\n", .{}) catch unreachable;
        }
        o.is_marked = true;

        if (vm.gray_stack.len < vm.gray_count + 1) {
            const gray_capacity = common.growCapacity(vm.gray_stack.len);
            vm.gray_stack = alloc.realloc(vm.gray_stack, gray_capacity) catch std.os.exit(1);
        }
        vm.gray_stack[vm.gray_count] = o;
        vm.gray_count += 1;
    }
}
