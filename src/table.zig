const std = @import("std");
const memory = @import("./memory.zig");
const common = @import("./common.zig");
const Value = @import("./value.zig").Value;
const object = @import("./object.zig");
const ObjString = object.ObjString;
const Obj = object.Obj;

const alloc = @import("./common.zig").alloc;

pub const Table = struct {
    const Self = @This();
    const max_load = 0.75;

    count: usize = 0,
    capacity: usize = 0,
    entries: [*]Entry = undefined,

    pub fn initTable() Self {
        return .{};
    }

    pub fn freeTable(self: *Self) void {
        memory.freeArray(Entry, self.entries, self.capacity);
        self.capacity = 0;
        self.count = 0;
    }

    pub fn tableSet(self: *Self, key: *ObjString, value: Value) bool {
        if (self.count + 1 > @floatToInt(usize, @intToFloat(f32, self.capacity) * max_load)) {
            const capacity = common.growCapacity(self.capacity);
            self.adjustCapacity(capacity);
        }
        const entry = findEntry(self.entries, self.capacity, key);
        const isNewKey = entry.key == null;
        if (isNewKey and entry.value.isNil()) self.count += 1;

        entry.key = key;
        entry.value = value;
        return isNewKey;
    }

    pub fn tableGet(self: *Self, key: *ObjString) ?Value {
        if (self.count == 0) return null;

        const entry = findEntry(self.entries, self.capacity, key);
        if (entry.key == null) return null;

        return entry.value;
    }

    pub fn tableDelete(self: *Self, key: *ObjString) bool {
        if (self.count == 0) return false;

        const entry = findEntry(self.entries, self.capacity, key);
        if (entry.key == null) return false;

        entry.key = null;
        entry.value = Value.Boolean(true);
        return true;
    }

    pub fn findString(self: *Self, chars: [*]const u8, length: usize, hash: u32) ?*ObjString {
        if (self.count == 0) return null;

        var index = hash % self.capacity;
        while (true) {
            const entry = &self.entries[index];
            if (entry.key == null) {
                if (entry.value.isNil()) return null;
            } else if (entry.key.?.hash == hash and std.mem.eql(u8, entry.key.?.chars[0..length], chars[0..length])) {
                return entry.key;
            }
            index = (index + 1) % self.capacity;
        }
    }

    pub fn removeWhite(self: *Self) void {
        for (self.entries[0..self.capacity]) |*entry| {
            if (entry.key) |key| {
                if (!key.obj.is_marked) {
                    _ = self.tableDelete(key);
                }
            }
        }
    }

    pub fn markTable(self: *Self) void {
        for (self.entries[0..self.capacity]) |*entry| {
            memory.markObject(@ptrCast(?*Obj, entry.key));
            memory.markValue(&entry.value);
        }
    }

    fn tableAddAll(to: *Self, from: *Self) void {
        for (from.entries[0..from.capacity]) |entry| {
            if (entry.key != null) {
                to.tableSet(entry.key, entry.value);
            }
        }
    }

    fn adjustCapacity(self: *Self, capacity: usize) void {
        const entries = memory.allocate(Entry, capacity);
        for (entries[0..capacity]) |*entry| {
            entry.key = null;
            entry.value = Value.Nil();
        }

        self.count = 0;
        for (self.entries[0..self.capacity]) |*entry| {
            if (entry.key == null) continue;
            const dest = findEntry(entries, capacity, entry.key.?);
            dest.key = entry.key;
            dest.value = entry.value;
            self.count += 1;
        }
        memory.freeArray(Entry, self.entries, self.capacity);

        self.entries = entries;
        self.capacity = capacity;
    }
};

const Entry = struct {
    key: ?*ObjString,
    value: Value,
};

fn findEntry(entries: [*]Entry, capacity: usize, key: *ObjString) *Entry {
    var index = key.hash % capacity;
    var tombstone: ?*Entry = null;
    while (true) {
        const entry = &entries[index];
        if (entry.key == null) {
            if (entry.value.isNil()) {
                return tombstone orelse entry;
            } else {
                if (tombstone == null) tombstone = entry;
            }
        } else if (entry.key == key) return entry;
        index = (index + 1) % capacity;
    }
}
