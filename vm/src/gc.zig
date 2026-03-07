// Garbage collection — mark-sweep (spec 05 §4).
const std = @import("std");
const Value = @import("value.zig").Value;

// Heap object kinds (must match exec.zig)
pub const RECORD_KIND: u8 = 1;
pub const ADT_KIND: u8 = 2;
pub const TASK_KIND: u8 = 3;
pub const STRING_KIND: u8 = 4;
pub const CLOSURE_KIND: u8 = 5;
pub const FLOAT_KIND: u8 = 6;

// Heap object layout:
// - RECORD: kind(1)+mark(1)+pad(2)+module_index(4)+shape_id(4)+field_count(4)+pad(4)=16, then field_count*8 bytes
// - ADT: kind(1)+mark(1)+pad(2)+module_index(4)+adt_id(4)+ctor(4)+arity(4)+pad(4)=24, then arity*8 bytes
// - CLOSURE: kind(1)+mark(1)+pad(2)+module_index(4)+fn_index(4)+pad(4)+env(8)=24
// - FLOAT: kind(1)+mark(1)+pad(6)+f64(8)=16
// Objects are 8-byte aligned
pub const RECORD_HEADER: usize = 16;
pub const FLOAT_HEADER: usize = 8;
pub const ADT_HEADER: usize = 24;
pub const CLOSURE_HEADER: usize = 24;

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

    /// Allocate a FLOAT heap object (kind FLOAT, f64 at offset 8). Returns Value.ptr to it.
    pub fn allocFloat(self: *GC, value: f64) !Value {
        const size: usize = 16; // FLOAT_HEADER + 8
        const mem = try self.allocObject(size);
        mem[0] = FLOAT_KIND;
        mem[1] = 0; // mark
        @as(*f64, @alignCast(@ptrCast(mem.ptr + FLOAT_HEADER))).* = value;
        return Value.ptr(@intFromPtr(mem.ptr));
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
                const field_count = std.mem.readInt(u32, base[12..16], .little);
                const fields_ptr = @as([*]Value, @alignCast(@ptrCast(base + RECORD_HEADER)));
                var i: usize = 0;
                while (i < field_count) : (i += 1) {
                    const field = fields_ptr[i];
                    if (field.tag == .ptr) {
                        self.mark(Value.ptrTo(field));
                    }
                }
            },
            ADT_KIND => {
                const arity = std.mem.readInt(u32, base[16..20], .little);
                const payloads_ptr = @as([*]Value, @alignCast(@ptrCast(base + ADT_HEADER)));
                var i: usize = 0;
                while (i < arity) : (i += 1) {
                    const field = payloads_ptr[i];
                    if (field.tag == .ptr) {
                        self.mark(Value.ptrTo(field));
                    }
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
            STRING_KIND => {
                // Strings: kind(1) + mark(1) + pad(2) + len(4) + UTF-8 bytes
                // No pointers to trace
            },
            CLOSURE_KIND => {
                // CLOSURE: env (PTR to RECORD) at offset 16
                const env_addr = std.mem.readInt(usize, base[16..24], .little);
                if (env_addr != 0) self.mark(env_addr);
            },
            FLOAT_KIND => {
                // FLOAT: no pointers to trace
            },
            else => {
                // Other kinds have no pointers to trace
            },
        }
    }

    pub fn markRoots(self: *GC, stack: []Value, all_locals: []const []const Value) void {
        // Mark from stack
        for (stack) |val| {
            if (val.tag == .ptr) {
                self.mark(Value.ptrTo(val));
            }
        }

        // Mark from every frame's locals (current + saved call frames)
        for (all_locals) |locals| {
            for (locals) |val| {
                if (val.tag == .ptr) {
                    self.mark(Value.ptrTo(val));
                }
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
                // Create aligned slice matching the allocation alignment (8 bytes = 2^3)
                const aligned_base = @as([*]align(8) u8, @alignCast(base));
                const mem: []align(8) u8 = aligned_base[0..size];
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

    pub fn collect(self: *GC, stack: []Value, all_locals: []const []const Value) void {
        self.markRoots(stack, all_locals);
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
            // Create aligned slice matching the allocation alignment (8 bytes = 2^3)
            const aligned_base = @as([*]align(8) u8, @alignCast(base));
            const mem: []align(8) u8 = aligned_base[0..size];
            self.allocator.free(mem);

            const next = node.next;
            self.allocator.destroy(node);
            current = next;
        }
    }
};
