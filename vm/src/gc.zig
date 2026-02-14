// Garbage collection — mark-sweep (spec 05 §4).
const std = @import("std");
const Value = @import("value.zig").Value;

// Heap object kinds (must match exec.zig)
pub const RECORD_KIND: u8 = 1;
pub const ADT_KIND: u8 = 2;
pub const TASK_KIND: u8 = 3;

// Heap object layout:
// Common: kind(1) + mark(1) + pad(2) + type_data(4) = 8 bytes header
// - For RECORD: type_data is field_count, followed by field_count * 8 bytes of Values
// - For ADT: type_data is ctor_tag, followed by payload Values
// Objects are 8-byte aligned

// Linked list of all allocated objects
pub const ObjectNode = struct {
    next: ?*ObjectNode,
    addr: usize,
    size: usize, // Size of the allocation for freeing
};

pub const GC = struct {
    allocator: std.mem.Allocator,
    objects: ?*ObjectNode,
    bytes_allocated: usize,
    next_gc: usize,

    const initial_threshold = 1024 * 1024; // 1 MB
    const growth_factor = 2;

    pub fn init(allocator: std.mem.Allocator) GC {
        return GC{
            .allocator = allocator,
            .objects = null,
            .bytes_allocated = 0,
            .next_gc = initial_threshold,
        };
    }

    pub fn allocObject(self: *GC, size: usize) ![]u8 {
        // Check if we should trigger GC
        if (self.bytes_allocated >= self.next_gc) {
            // GC would be triggered here, but we need roots
            // For now, just increase threshold
            self.next_gc = self.bytes_allocated * growth_factor;
        }

        // Allocate with 8-byte alignment (2^3 = 8)
        const mem = try self.allocator.alignedAlloc(u8, @enumFromInt(3), size);

        // Track this allocation
        const node = try self.allocator.create(ObjectNode);
        node.* = ObjectNode{
            .next = self.objects,
            .addr = @intFromPtr(mem.ptr),
            .size = size,
        };
        self.objects = node;
        self.bytes_allocated += size;

        return mem;
    }

    pub fn mark(self: *GC, addr: usize) void {
        if (addr == 0) return;

        const base = @as([*]u8, @ptrFromInt(addr));
        const kind = base[0];
        const mark_byte = base[1];

        // Already marked?
        if (mark_byte != 0) return;
        base[1] = 1; // Set mark bit

        // Mark children based on object kind
        switch (kind) {
            RECORD_KIND => {
                // Records: kind(1) + mark(1) + pad(2) + field_count(4) + fields
                const field_count = std.mem.readInt(u32, base[4..8], .little);
                const fields_ptr = @as([*]Value, @alignCast(@ptrCast(base + 8)));
                var i: usize = 0;
                while (i < field_count) : (i += 1) {
                    const field = fields_ptr[i];
                    if (field.tag == .ptr) {
                        self.mark(Value.ptrTo(field));
                    }
                }
            },
            ADT_KIND => {
                // ADTs: kind(1) + mark(1) + pad(2) + ctor_tag(4) + fields
                // We need to know arity to know how many fields to trace
                // For now, find this object in our tracking list to get size
                var current = self.objects;
                while (current) |node| {
                    if (node.addr == addr) {
                        const fields_size = node.size - 8;
                        const field_count = fields_size / 8;
                        const fields_ptr = @as([*]Value, @alignCast(@ptrCast(base + 8)));
                        var i: usize = 0;
                        while (i < field_count) : (i += 1) {
                            const field = fields_ptr[i];
                            if (field.tag == .ptr) {
                                self.mark(Value.ptrTo(field));
                            }
                        }
                        break;
                    }
                    current = node.next;
                }
            },
            TASK_KIND => {
                // Tasks: kind(1) + mark(1) + status(1) + pad(1) + unused(4) + result(8)
                // Mark the result value if it's a pointer
                const result_ptr = @as(*const Value, @alignCast(@ptrCast(base + 8)));
                const result = result_ptr.*;
                if (result.tag == .ptr) {
                    self.mark(Value.ptrTo(result));
                }
            },
            else => {
                // Other kinds (FLOAT, STRING, etc.) have no pointers to trace
            },
        }
    }

    pub fn markRoots(self: *GC, stack: []Value, locals: []Value) void {
        // Mark from stack
        for (stack) |val| {
            if (val.tag == .ptr) {
                self.mark(Value.ptrTo(val));
            }
        }

        // Mark from locals
        for (locals) |val| {
            if (val.tag == .ptr) {
                self.mark(Value.ptrTo(val));
            }
        }
    }

    pub fn sweep(self: *GC) void {
        var prev: ?*ObjectNode = null;
        var current = self.objects;

        while (current) |node| {
            const base = @as([*]u8, @ptrFromInt(node.addr));
            const mark_byte = base[1];

            if (mark_byte == 0) {
                // Unmarked: free this object
                const size = node.size;
                const mem: []u8 = base[0..size];
                self.allocator.free(mem);
                self.bytes_allocated -= size;

                // Remove from list
                const next = node.next;
                if (prev) |p| {
                    p.next = next;
                } else {
                    self.objects = next;
                }
                self.allocator.destroy(node);
                current = next;
            } else {
                // Marked: unmark for next cycle and keep
                base[1] = 0;
                prev = node;
                current = node.next;
            }
        }
    }

    pub fn collect(self: *GC, stack: []Value, locals: []Value) void {
        self.markRoots(stack, locals);
        self.sweep();

        // Adjust next GC threshold
        self.next_gc = @max(self.bytes_allocated * growth_factor, initial_threshold);
    }

    pub fn deinit(self: *GC) void {
        // Free all remaining objects
        var current = self.objects;
        while (current) |node| {
            const base = @as([*]u8, @ptrFromInt(node.addr));
            const size = node.size;
            const mem: []u8 = base[0..size];
            self.allocator.free(mem);

            const next = node.next;
            self.allocator.destroy(node);
            current = next;
        }
    }
};
