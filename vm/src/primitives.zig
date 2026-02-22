// Minimal VM primitives (Phase 5). Stdlib .ks calls these; VM dispatches CALL to primitive by name.
const std = @import("std");
const Value = @import("value.zig").Value;
const gc_mod = @import("gc.zig");
const GC = gc_mod.GC;

// Value ADT constructor tags (spec 02, codegen.ts)
const VALUE_NULL: u32 = 0;
const VALUE_BOOL: u32 = 1;
const VALUE_INT: u32 = 2;
const VALUE_FLOAT: u32 = 3;
const VALUE_STRING: u32 = 4;
const VALUE_ARRAY: u32 = 5;
const VALUE_OBJECT: u32 = 6;
// List ADT
const LIST_NIL: u32 = 0;
const LIST_CONS: u32 = 1;

/// Format a single value to a string (no newline). Caller must have enough buffer.
pub fn formatOne(val: Value, out: []u8) []const u8 {
    return switch (val.tag) {
        .int => std.fmt.bufPrint(out, "{d}", .{Value.intTo(val)}) catch return "<value>",
        .bool => std.fmt.bufPrint(out, "{}", .{val.payload != 0}) catch return "<value>",
        .unit => std.fmt.bufPrint(out, "()", .{}) catch return "<value>",
        .char => blk: {
            const c = @as(u21, @intCast(val.payload));
            var cbuf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(c, &cbuf) catch 1;
            break :blk std.fmt.bufPrint(out, "{s}", .{cbuf[0..len]}) catch "<value>";
        },
        .ptr => blk: {
            const addr = Value.ptrTo(val);
            if (addr == 0) break :blk std.fmt.bufPrint(out, "()", .{}) catch return "<value>";

            const base = @as([*]const u8, @ptrFromInt(addr));
            const kind = base[0];

            if (kind == 4) { // STRING_KIND
                const len = std.mem.readInt(u32, base[4..8], .little);
                const str_data = base[8..8+len];
                break :blk std.fmt.bufPrint(out, "{s}", .{str_data}) catch "<value>";
            }

            break :blk std.fmt.bufPrint(out, "<value>", .{}) catch "<value>";
        },
        else => std.fmt.bufPrint(out, "<value>", .{}) catch "<value>",
    };
}

/// Print N values to stdout, space-separated, with optional trailing newline (built-in print/println).
pub fn printN(values: []const Value, trailing_newline: bool) void {
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var part: [256]u8 = undefined;
    for (values, 0..) |val, i| {
        if (i > 0) _ = stdout.write(" ") catch {};
        const s = formatOne(val, &part);
        _ = stdout.write(s) catch {};
    }
    if (trailing_newline) _ = stdout.write("\n") catch {};
}

/// Print a single value to stdout (legacy; adds newline). Prefer printN for built-in print/println.
pub fn print(val: Value) void {
    printN(&.{val}, true);
}

/// Print an integer (for stdlib)
pub fn printInt(n: i64) void {
    var buf: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();
    const output = std.fmt.allocPrint(allocator, "{d}\n", .{n}) catch return;
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    _ = stdout.write(output) catch {};
}

pub fn writeStdoutString(_: std.mem.Allocator, _: Value) void {
    // TODO: resolve string value (PTR to STRING heap), write UTF-8 to stdout
}

/// If val is a PTR to a STRING heap object, return the UTF-8 slice; else null.
pub fn getStringSlice(val: Value) ?[]const u8 {
    if (val.tag != .ptr) return null;
    const addr = Value.ptrTo(val);
    if (addr == 0) return null;
    const base = @as([*]const u8, @ptrFromInt(addr));
    if (base[0] != 4) return null; // STRING_KIND
    const len = std.mem.readInt(u32, base[4..8], .little);
    return base[8..8+len];
}

/// Allocate a Value ADT (Null, Bool, Int, String, Array; Object and Float stubbed).
fn allocValueAdt(gc: *GC, ctor: u32, payload: ?Value) !Value {
    const arity: usize = if (payload != null) 1 else 0;
    const mem = try gc.allocObject(8 + arity * 8);
    @memset(mem, 0);
    mem[0] = gc_mod.ADT_KIND;
    mem[1] = 0;
    std.mem.writeInt(u32, mem[4..8], ctor, .little);
    if (payload) |p| {
        const fields = @as([*]Value, @alignCast(@ptrCast(mem.ptr + 8)));
        fields[0] = p;
    }
    return Value.ptr(@intFromPtr(mem.ptr));
}

/// Allocate a List ADT (Nil or Cons).
fn allocListAdt(gc: *GC, ctor: u32, head: ?Value, tail: ?Value) !Value {
    const arity: usize = if (ctor == LIST_CONS) 2 else 0;
    const mem = try gc.allocObject(8 + arity * 8);
    @memset(mem, 0);
    mem[0] = gc_mod.ADT_KIND;
    mem[1] = 0;
    std.mem.writeInt(u32, mem[4..8], ctor, .little);
    if (head != null and tail != null) {
        const fields = @as([*]Value, @alignCast(@ptrCast(mem.ptr + 8)));
        fields[0] = head.?;
        fields[1] = tail.?;
    }
    return Value.ptr(@intFromPtr(mem.ptr));
}

/// Allocate a STRING heap object.
fn allocString(gc: *GC, slice: []const u8) !Value {
    const total = 8 + slice.len;
    const mem = try gc.allocObject(total);
    @memset(mem, 0);
    mem[0] = gc_mod.STRING_KIND;
    std.mem.writeInt(u32, mem[4..8], @as(u32, @intCast(slice.len)), .little);
    @memcpy(mem[8..][0..slice.len], slice);
    return Value.ptr(@intFromPtr(mem.ptr));
}

fn jsonToValue(gc: *GC, j: std.json.Value) !Value {
    return switch (j) {
        .null => allocValueAdt(gc, VALUE_NULL, null),
        .bool => |b| allocValueAdt(gc, VALUE_BOOL, Value.boolVal(b)),
        .integer => |i| allocValueAdt(gc, VALUE_INT, Value.int(@intCast(i))),
        .float => |f| allocValueAdt(gc, VALUE_FLOAT, Value.int(@bitCast(f))), // store f64 bits in int payload for now
        .number_string => |s| allocValueAdt(gc, VALUE_STRING, try allocString(gc, s)),
        .string => |s| allocValueAdt(gc, VALUE_STRING, try allocString(gc, s)),
        .array => |arr| blk: {
            var tail: Value = try allocListAdt(gc, LIST_NIL, null, null);
            const items = arr.items;
            var i = items.len;
            while (i > 0) {
                i -= 1;
                const head = try jsonToValue(gc, items[i]);
                tail = try allocListAdt(gc, LIST_CONS, head, tail);
            }
            break :blk allocValueAdt(gc, VALUE_ARRAY, tail);
        },
        .object => allocValueAdt(gc, VALUE_OBJECT, try allocListAdt(gc, LIST_NIL, null, null)), // stub: empty list
    };
}

/// Parse JSON string to Value ADT. Returns Null on parse error.
pub fn jsonParse(gc: *GC, string_val: Value) Value {
    const slice = getStringSlice(string_val) orelse return allocValueAdt(gc, VALUE_NULL, null) catch Value.ptr(0);
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, slice, .{ .allocate = .alloc_always }) catch return allocValueAdt(gc, VALUE_NULL, null) catch Value.ptr(0);
    defer parsed.deinit();
    return jsonToValue(gc, parsed.value) catch return allocValueAdt(gc, VALUE_NULL, null) catch Value.ptr(0);
}

fn valueAdtCtor(base: [*]const u8) u32 {
    return std.mem.readInt(u32, base[4..8], .little);
}

fn valueAdtPayload(base: [*]const u8) Value {
    const fields = @as([*]const Value, @alignCast(@ptrCast(base + 8)));
    return fields[0];
}

const page_alloc = std.heap.page_allocator;

fn valueToString(gc: *GC, val: Value, out: *std.ArrayList(u8)) !void {
    if (val.tag != .ptr) return;
    const addr = Value.ptrTo(val);
    if (addr == 0) return;
    const base = @as([*]const u8, @ptrFromInt(addr));
    if (base[0] != gc_mod.ADT_KIND) return;
    const ctor = valueAdtCtor(base);
    switch (ctor) {
        VALUE_NULL => try out.appendSlice(page_alloc, "null"),
        VALUE_BOOL => {
            const p = valueAdtPayload(base);
            if (p.payload != 0) try out.appendSlice(page_alloc, "true") else try out.appendSlice(page_alloc, "false");
        },
        VALUE_INT => {
            const p = valueAdtPayload(base);
            try std.fmt.format(out.writer(page_alloc), "{d}", .{Value.intTo(p)});
        },
        VALUE_FLOAT => {
            const p = valueAdtPayload(base);
            const bits: u64 = @as(u64, p.payload);
            const f = @as(f64, @bitCast(bits));
            try std.fmt.format(out.writer(page_alloc), "{d}", .{f});
        },
        VALUE_STRING => {
            const p = valueAdtPayload(base);
            const s = getStringSlice(p) orelse return;
            try out.append(page_alloc, '"');
            for (s) |c| {
                switch (c) {
                    '"' => try out.appendSlice(page_alloc, "\\\""),
                    '\\' => try out.appendSlice(page_alloc, "\\\\"),
                    '\n' => try out.appendSlice(page_alloc, "\\n"),
                    '\r' => try out.appendSlice(page_alloc, "\\r"),
                    '\t' => try out.appendSlice(page_alloc, "\\t"),
                    else => try out.append(page_alloc, c),
                }
            }
            try out.append(page_alloc, '"');
        },
        VALUE_ARRAY => {
            try out.appendSlice(page_alloc, "[");
            var list = valueAdtPayload(base);
            var first = true;
            while (list.tag == .ptr and Value.ptrTo(list) != 0) {
                const list_base = @as([*]const u8, @ptrFromInt(Value.ptrTo(list)));
                if (list_base[0] != gc_mod.ADT_KIND) break;
                if (valueAdtCtor(list_base) != LIST_CONS) break;
                const fields = @as([*]const Value, @alignCast(@ptrCast(list_base + 8)));
                if (!first) try out.appendSlice(page_alloc, ",");
                try valueToString(gc, fields[0], out);
                first = false;
                list = fields[1];
            }
            try out.appendSlice(page_alloc, "]");
        },
        VALUE_OBJECT => try out.appendSlice(page_alloc, "{}"), // stub
        else => {},
    }
}

/// Serialise Value ADT to JSON string. Allocates result string on GC.
pub fn jsonStringify(gc: *GC, value_val: Value) Value {
    var out = std.ArrayList(u8).initCapacity(std.heap.page_allocator, 4096) catch return Value.ptr(0);
    defer out.deinit(std.heap.page_allocator);
    valueToString(gc, value_val, &out) catch return Value.ptr(0);
    return allocString(gc, out.items) catch return Value.ptr(0);
}

/// Read file contents as UTF-8; returns a completed Task<String>. Synchronous for now.
pub fn readFileAsync(gc: *GC, path_val: Value) Value {
    const path_slice = getStringSlice(path_val) orelse return completedTaskWith(gc, Value.ptr(0));
    const file = std.fs.cwd().openFile(path_slice, .{}) catch return completedTaskWith(gc, Value.ptr(0));
    defer file.close();
    const content = file.readToEndAlloc(std.heap.page_allocator, 1024 * 1024) catch return completedTaskWith(gc, Value.ptr(0));
    defer std.heap.page_allocator.free(content);
    const str_val = allocString(gc, content) catch return completedTaskWith(gc, Value.ptr(0));
    return completedTaskWith(gc, str_val);
}

fn completedTaskWith(gc: *GC, result: Value) Value {
    const mem = gc.allocObject(16) catch return Value.ptr(0);
    @memset(mem, 0);
    mem[0] = gc_mod.TASK_KIND;
    mem[2] = 1; // status = completed
    const result_ptr = @as(*Value, @alignCast(@ptrCast(mem.ptr + 8)));
    result_ptr.* = result;
    return Value.ptr(@intFromPtr(mem.ptr));
}

/// Current time in milliseconds (for kestrel:http nowMs).
pub fn nowMs() Value {
    const ms = std.time.milliTimestamp();
    return Value.int(@intCast(ms));
}

// --- String primitives (kestrel:string) ---

/// (String) -> Int: character length in UTF-8 bytes.
pub fn stringLength(s_val: Value) Value {
    const s = getStringSlice(s_val) orelse return Value.int(0);
    return Value.int(@intCast(s.len));
}

/// (String, Int, Int) -> String: substring [start, end). Clamps to valid range.
pub fn stringSlice(gc: *GC, s_val: Value, start_val: Value, end_val: Value) Value {
    const s = getStringSlice(s_val) orelse return Value.ptr(0);
    var start = Value.intTo(start_val);
    var end = Value.intTo(end_val);
    if (start < 0) start = 0;
    if (end > @as(i64, @intCast(s.len))) end = @intCast(s.len);
    if (start >= end) return allocString(gc, s[0..0]) catch Value.ptr(0);
    const su = @as(usize, @intCast(start));
    const eu = @as(usize, @intCast(end));
    if (eu > s.len) return allocString(gc, s[0..0]) catch Value.ptr(0);
    return allocString(gc, s[su..eu]) catch Value.ptr(0);
}

/// (String, String) -> Int: index of first occurrence of sub in s, or -1.
pub fn stringIndexOf(s_val: Value, sub_val: Value) Value {
    const s = getStringSlice(s_val) orelse return Value.int(-1);
    const sub = getStringSlice(sub_val) orelse return Value.int(-1);
    const idx = std.mem.indexOf(u8, s, sub) orelse return Value.int(-1);
    return Value.int(@intCast(idx));
}

/// (String, String) -> Bool: value equality.
pub fn stringEquals(a_val: Value, b_val: Value) Value {
    const a = getStringSlice(a_val) orelse return Value.boolVal(false);
    const b = getStringSlice(b_val) orelse return Value.boolVal(false);
    return Value.boolVal(std.mem.eql(u8, a, b));
}

/// (String) -> String: uppercase copy (ASCII only for simplicity).
pub fn stringUpper(gc: *GC, s_val: Value) Value {
    const s = getStringSlice(s_val) orelse return Value.ptr(0);
    var out = std.ArrayList(u8).initCapacity(page_alloc, s.len) catch return Value.ptr(0);
    defer out.deinit(page_alloc);
    for (s) |c| {
        const up = if (c >= 'a' and c <= 'z') c - 32 else c;
        out.append(page_alloc, up) catch return Value.ptr(0);
    }
    return allocString(gc, out.items) catch Value.ptr(0);
}
