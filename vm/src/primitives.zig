// Minimal VM primitives (Phase 5). Stdlib .ks calls these; VM dispatches CALL to primitive by name.
const std = @import("std");
const Value = @import("value.zig").Value;
const gc_mod = @import("gc.zig");
const load_mod = @import("load.zig");
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
// ADT table indices (codegen: List=0, Option=1, Result=2, Value=3)
const LIST_ADT_ID: u32 = 0;
const VALUE_ADT_ID: u32 = 3;

fn appendSlice(buf: []u8, pos: *usize, s: []const u8) bool {
    if (pos.* + s.len > buf.len) return false;
    @memcpy(buf[pos.*..][0..s.len], s);
    pos.* += s.len;
    return true;
}

/// Format a value into buf starting at start; returns new position or null if buffer too small.
fn formatInto(val: Value, buf: []u8, start: usize, module_cache: ?[]const *const load_mod.Module) ?usize {
    if (start >= buf.len) return null;
    var pos = start;
    switch (val.tag) {
        .int => {
            const written = std.fmt.bufPrint(buf[pos..], "{d}", .{Value.intTo(val)}) catch return null;
            return pos + written.len;
        },
        .bool => {
            const s = if (val.payload != 0) "true" else "false";
            if (pos + s.len > buf.len) return null;
            @memcpy(buf[pos..][0..s.len], s);
            return pos + s.len;
        },
        .unit => {
            if (pos + 2 > buf.len) return null;
            buf[pos] = '(';
            buf[pos + 1] = ')';
            return pos + 2;
        },
        .char => {
            const c = @as(u21, @intCast(val.payload));
            var cbuf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(c, &cbuf) catch 1;
            if (pos + len > buf.len) return null;
            @memcpy(buf[pos..][0..len], cbuf[0..len]);
            return pos + len;
        },
        .ptr => {
            const addr = Value.ptrTo(val);
            if (addr == 0) {
                if (pos + 2 > buf.len) return null;
                buf[pos] = '(';
                buf[pos + 1] = ')';
                return pos + 2;
            }
            const base = @as([*]const u8, @ptrFromInt(addr));
            const kind = base[0];
            if (kind == gc_mod.STRING_KIND) {
                const len = std.mem.readInt(u32, base[4..8], .little);
                const str_data = base[8..8+len];
                if (pos + str_data.len > buf.len) return null;
                @memcpy(buf[pos..][0..str_data.len], str_data);
                return pos + str_data.len;
            }
            if (kind == gc_mod.FLOAT_KIND) {
                const f = @as(*const f64, @alignCast(@ptrCast(base + gc_mod.FLOAT_HEADER))).*;
                const written = std.fmt.bufPrint(buf[pos..], "{d}", .{f}) catch return null;
                return pos + written.len;
            }
            if (kind == gc_mod.RECORD_KIND) {
                const field_count = std.mem.readInt(u32, base[12..16], .little);
                const fields = @as([*]const Value, @alignCast(@ptrCast(base + gc_mod.RECORD_HEADER)));
                if (module_cache) |cache| {
                    const mod_idx = std.mem.readInt(u32, base[4..8], .little);
                    const shape_id = std.mem.readInt(u32, base[8..12], .little);
                    if (mod_idx < cache.len and cache[mod_idx].*.shapes.len > shape_id) {
                        const shape = &cache[mod_idx].*.shapes[shape_id];
                        if (!appendSlice(buf, &pos, "{ ")) return null;
                        var i: usize = 0;
                        while (i < field_count) : (i += 1) {
                            if (i > 0 and !appendSlice(buf, &pos, ", ")) return null;
                            if (i < shape.field_names.len and !appendSlice(buf, &pos, shape.field_names[i])) return null;
                            if (!appendSlice(buf, &pos, " = ")) return null;
                            const next = formatInto(fields[i], buf, pos, module_cache) orelse return null;
                            pos = next;
                        }
                        if (!appendSlice(buf, &pos, " }")) return null;
                        return pos;
                    }
                }
                if (!appendSlice(buf, &pos, "{ ")) return null;
                var i: usize = 0;
                while (i < field_count) : (i += 1) {
                    if (i > 0 and !appendSlice(buf, &pos, ", ")) return null;
                    const next = formatInto(fields[i], buf, pos, module_cache) orelse return null;
                    pos = next;
                }
                if (!appendSlice(buf, &pos, " }")) return null;
                return pos;
            }
            if (kind == gc_mod.ADT_KIND) {
                const layout_ver = base[2];
                if (layout_ver == 1 and module_cache != null and module_cache.?.len > 0) {
                    const mod_idx = std.mem.readInt(u32, base[4..8], .little);
                    const adt_id = std.mem.readInt(u32, base[8..12], .little);
                    const ctor = std.mem.readInt(u32, base[12..16], .little);
                    const arity = std.mem.readInt(u32, base[16..20], .little);
                    const payloads = @as([*]const Value, @alignCast(@ptrCast(base + gc_mod.ADT_HEADER)));
                    const cache = module_cache.?;
                    if (mod_idx < cache.len and cache[mod_idx].*.adts.len > adt_id) {
                        const adt = &cache[mod_idx].*.adts[adt_id];
                        const is_list = adt.name.len == 4 and std.mem.eql(u8, adt.name, "List");
                        if (is_list and adt.constructor_names.len >= 2 and ctor == 0) {
                            if (!appendSlice(buf, &pos, "[]")) return null;
                            return pos;
                        }
                        if (is_list and ctor == 1 and arity >= 2) {
                            if (!appendSlice(buf, &pos, "[")) return null;
                            var first = true;
                            var tail = val;
                            while (true) {
                                const tail_addr = Value.ptrTo(tail);
                                if (tail_addr == 0) break;
                                const tb = @as([*]const u8, @ptrFromInt(tail_addr));
                                if (tb[0] != gc_mod.ADT_KIND or tb[2] != 1) break;
                                const tctor = std.mem.readInt(u32, tb[12..16], .little);
                                if (tctor == 0) break;
                                if (tctor != 1) break;
                                const tf = @as([*]const Value, @alignCast(@ptrCast(tb + gc_mod.ADT_HEADER)));
                                if (!first and !appendSlice(buf, &pos, ", ")) return null;
                                const next = formatInto(tf[0], buf, pos, module_cache) orelse return null;
                                pos = next;
                                first = false;
                                tail = tf[1];
                            }
                            if (!appendSlice(buf, &pos, "]")) return null;
                            return pos;
                        }
                        if (ctor < adt.constructor_names.len) {
                            if (!appendSlice(buf, &pos, adt.constructor_names[ctor])) return null;
                            if (arity > 0) {
                                if (!appendSlice(buf, &pos, "(")) return null;
                                var i: usize = 0;
                                while (i < arity) : (i += 1) {
                                    if (i > 0 and !appendSlice(buf, &pos, ", ")) return null;
                                    const next = formatInto(payloads[i], buf, pos, module_cache) orelse return null;
                                    pos = next;
                                }
                                if (!appendSlice(buf, &pos, ")")) return null;
                            }
                            return pos;
                        }
                    }
                }
                const fallback = "<value>";
                if (pos + fallback.len > buf.len) return null;
                @memcpy(buf[pos..][0..fallback.len], fallback);
                return pos + fallback.len;
            }
            const fallback = "<value>";
            if (pos + fallback.len > buf.len) return null;
            @memcpy(buf[pos..][0..fallback.len], fallback);
            return pos + fallback.len;
        },
        else => {
            const fallback = "<value>";
            if (pos + fallback.len > buf.len) return null;
            @memcpy(buf[pos..][0..fallback.len], fallback);
            return pos + fallback.len;
        },
    }
}

/// Format a single value to a string (no newline). Caller must have enough buffer (e.g. 4096 for nested values).
pub fn formatOne(val: Value, out: []u8, module_cache: ?[]const *const load_mod.Module) []const u8 {
    if (formatInto(val, out, 0, module_cache)) |end| return out[0..end];
    return "<value>";
}

/// Print N values to stdout, space-separated, with optional trailing newline (built-in print/println).
pub fn printN(values: []const Value, trailing_newline: bool, module_cache: ?[]const *const load_mod.Module) void {
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var part: [4096]u8 = undefined;
    for (values, 0..) |val, i| {
        if (i > 0) _ = stdout.write(" ") catch {};
        const s = formatOne(val, &part, module_cache);
        _ = stdout.write(s) catch {};
    }
    if (trailing_newline) _ = stdout.write("\n") catch {};
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

/// Returns true if every byte in s is < 0x80 (ASCII). Used as fast path for codepoint operations.
fn utf8IsAscii(s: []const u8) bool {
    for (s) |b| {
        if (b >= 0x80) return false;
    }
    return true;
}

/// Count Unicode code points. Fast path: if s is all ASCII, returns s.len.
fn utf8CountCodepoints(s: []const u8) usize {
    if (utf8IsAscii(s)) return s.len;
    const view = std.unicode.Utf8View.init(s) catch return s.len;
    var count: usize = 0;
    var iter = view.iterator();
    while (iter.nextCodepointSlice()) |_| count += 1;
    return count;
}

/// Returns the byte offset of the cp_index-th code point (0-based), or null if cp_index is past the end.
fn utf8ByteOffsetForCodepoint(s: []const u8, cp_index: usize) ?usize {
    if (utf8IsAscii(s)) {
        if (cp_index > s.len) return null;
        return cp_index;
    }
    const view = std.unicode.Utf8View.init(s) catch return null;
    var iter = view.iterator();
    var start: usize = 0;
    var count: usize = 0;
    while (iter.nextCodepointSlice()) |_| {
        if (count == cp_index) return start;
        start = iter.i;
        count += 1;
    }
    return null;
}

/// Allocate a Value ADT (Null, Bool, Int, String, Array; Object and Float stubbed). Uses current ADT layout (layout_ver 1).
fn allocValueAdt(gc: *GC, module_index: u32, ctor: u32, payload: ?Value) !Value {
    const arity: u32 = if (payload != null) 1 else 0;
    const mem = try gc.allocObject(gc_mod.ADT_HEADER + arity * 8);
    @memset(mem, 0);
    mem[0] = gc_mod.ADT_KIND;
    mem[1] = 0;
    mem[2] = 1;
    std.mem.writeInt(u32, mem[4..8], module_index, .little);
    std.mem.writeInt(u32, mem[8..12], VALUE_ADT_ID, .little);
    std.mem.writeInt(u32, mem[12..16], ctor, .little);
    std.mem.writeInt(u32, mem[16..20], arity, .little);
    if (payload) |p| {
        const fields = @as([*]Value, @alignCast(@ptrCast(mem.ptr + gc_mod.ADT_HEADER)));
        fields[0] = p;
    }
    return Value.ptr(@intFromPtr(mem.ptr));
}

/// Allocate a List ADT (Nil or Cons). Uses current ADT layout (layout_ver 1).
fn allocListAdt(gc: *GC, module_index: u32, ctor: u32, head: ?Value, tail: ?Value) !Value {
    const arity: u32 = if (ctor == LIST_CONS) 2 else 0;
    const mem = try gc.allocObject(gc_mod.ADT_HEADER + arity * 8);
    @memset(mem, 0);
    mem[0] = gc_mod.ADT_KIND;
    mem[1] = 0;
    mem[2] = 1;
    std.mem.writeInt(u32, mem[4..8], module_index, .little);
    std.mem.writeInt(u32, mem[8..12], LIST_ADT_ID, .little);
    std.mem.writeInt(u32, mem[12..16], ctor, .little);
    std.mem.writeInt(u32, mem[16..20], arity, .little);
    if (head != null and tail != null) {
        const fields = @as([*]Value, @alignCast(@ptrCast(mem.ptr + gc_mod.ADT_HEADER)));
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

fn jsonToValue(gc: *GC, j: std.json.Value, module_index: u32) !Value {
    return switch (j) {
        .null => allocValueAdt(gc, module_index, VALUE_NULL, null),
        .bool => |b| allocValueAdt(gc, module_index, VALUE_BOOL, Value.boolVal(b)),
        .integer => |i| allocValueAdt(gc, module_index, VALUE_INT, Value.int(@intCast(i))),
        .float => |f| blk: {
            const float_val = gc.allocFloat(f) catch break :blk try allocValueAdt(gc, module_index, VALUE_NULL, null);
            break :blk try allocValueAdt(gc, module_index, VALUE_FLOAT, float_val);
        },
        .number_string => |s| allocValueAdt(gc, module_index, VALUE_STRING, try allocString(gc, s)),
        .string => |s| allocValueAdt(gc, module_index, VALUE_STRING, try allocString(gc, s)),
        .array => |arr| blk: {
            var tail: Value = try allocListAdt(gc, module_index, LIST_NIL, null, null);
            const items = arr.items;
            var i = items.len;
            while (i > 0) {
                i -= 1;
                const head = try jsonToValue(gc, items[i], module_index);
                tail = try allocListAdt(gc, module_index, LIST_CONS, head, tail);
            }
            break :blk allocValueAdt(gc, module_index, VALUE_ARRAY, tail);
        },
        .object => allocValueAdt(gc, module_index, VALUE_OBJECT, try allocListAdt(gc, module_index, LIST_NIL, null, null)), // stub: empty list
    };
}

/// Parse JSON string to Value ADT. Returns Null on parse error. module_index is the current module for ADT identity.
pub fn jsonParse(gc: *GC, string_val: Value, module_index: u32) Value {
    const slice = getStringSlice(string_val) orelse return allocValueAdt(gc, module_index, VALUE_NULL, null) catch Value.ptr(0);
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, slice, .{ .allocate = .alloc_always }) catch return allocValueAdt(gc, module_index, VALUE_NULL, null) catch Value.ptr(0);
    defer parsed.deinit();
    return jsonToValue(gc, parsed.value, module_index) catch return allocValueAdt(gc, module_index, VALUE_NULL, null) catch Value.ptr(0);
}

fn valueAdtCtor(base: [*]const u8) u32 {
    return std.mem.readInt(u32, base[12..16], .little);
}

fn valueAdtPayload(base: [*]const u8) Value {
    const fields = @as([*]const Value, @alignCast(@ptrCast(base + gc_mod.ADT_HEADER)));
    return fields[0];
}

const page_alloc = std.heap.page_allocator;

fn valueToString(gc: *GC, val: Value, out: *std.ArrayList(u8)) !void {
    if (val.tag != .ptr) return;
    const addr = Value.ptrTo(val);
    if (addr == 0) return;
    const base = @as([*]const u8, @ptrFromInt(addr));
    if (base[0] != gc_mod.ADT_KIND or base[2] != 1) return;
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
            if (p.tag != .ptr) return;
            const float_addr = Value.ptrTo(p);
            if (float_addr == 0) return;
            const fbase = @as([*]const u8, @ptrFromInt(float_addr));
            if (fbase[0] != gc_mod.FLOAT_KIND) return;
            const f = @as(*const f64, @alignCast(@ptrCast(fbase + gc_mod.FLOAT_HEADER))).*;
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
                if (list_base[0] != gc_mod.ADT_KIND or list_base[2] != 1) break;
                if (valueAdtCtor(list_base) != LIST_CONS) break;
                const fields = @as([*]const Value, @alignCast(@ptrCast(list_base + gc_mod.ADT_HEADER)));
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

/// (String) -> Int: character length (Unicode code points). ASCII fast path.
pub fn stringLength(s_val: Value) Value {
    const s = getStringSlice(s_val) orelse return Value.int(0);
    const n = if (utf8IsAscii(s)) s.len else utf8CountCodepoints(s);
    return Value.int(@intCast(n));
}

/// (String, Int, Int) -> String: substring [start, end) by character index. Clamps to valid range.
pub fn stringSlice(gc: *GC, s_val: Value, start_val: Value, end_val: Value) Value {
    const s = getStringSlice(s_val) orelse return Value.ptr(0);
    var start = Value.intTo(start_val);
    var end = Value.intTo(end_val);
    const cp_count: i64 = if (utf8IsAscii(s)) @intCast(s.len) else @intCast(utf8CountCodepoints(s));
    if (start < 0) start = 0;
    if (end > cp_count) end = cp_count;
    if (start >= end) return allocString(gc, s[0..0]) catch Value.ptr(0);
    const su = @as(usize, @intCast(start));
    const eu = @as(usize, @intCast(end));
    if (utf8IsAscii(s)) {
        if (eu > s.len) return allocString(gc, s[0..0]) catch Value.ptr(0);
        return allocString(gc, s[su..eu]) catch Value.ptr(0);
    }
    const byte_start = utf8ByteOffsetForCodepoint(s, su) orelse return allocString(gc, s[0..0]) catch Value.ptr(0);
    const byte_end = if (eu == cp_count) s.len else (utf8ByteOffsetForCodepoint(s, eu) orelse s.len);
    if (byte_end > s.len or byte_start >= byte_end) return allocString(gc, s[0..0]) catch Value.ptr(0);
    return allocString(gc, s[byte_start..byte_end]) catch Value.ptr(0);
}

/// (String, String) -> Int: character index of first occurrence of sub in s, or -1.
pub fn stringIndexOf(s_val: Value, sub_val: Value) Value {
    const s = getStringSlice(s_val) orelse return Value.int(-1);
    const sub = getStringSlice(sub_val) orelse return Value.int(-1);
    const byte_idx = std.mem.indexOf(u8, s, sub) orelse return Value.int(-1);
    if (utf8IsAscii(s[0..byte_idx])) return Value.int(@intCast(byte_idx));
    const prefix = s[0..byte_idx];
    const cp_idx = utf8CountCodepoints(prefix);
    return Value.int(@intCast(cp_idx));
}

/// (String, String) -> Bool: value equality.
pub fn stringEquals(a_val: Value, b_val: Value) Value {
    const a = getStringSlice(a_val) orelse return Value.boolVal(false);
    const b = getStringSlice(b_val) orelse return Value.boolVal(false);
    return Value.boolVal(std.mem.eql(u8, a, b));
}

/// Deep structural equality: (T, T) -> Bool
pub fn equals(a: Value, b: Value) Value {
    return Value.boolVal(deepEqual(a, b));
}

fn deepEqual(a: Value, b: Value) bool {
    if (a.tag != b.tag) return false;
    switch (a.tag) {
        .int, .bool, .char => return a.payload == b.payload,
        .unit => return true,
        .ptr => {
            const addr_a = Value.ptrTo(a);
            const addr_b = Value.ptrTo(b);
            if (addr_a == 0 and addr_b == 0) return true;
            if (addr_a == 0 or addr_b == 0) return false;
            const base_a = @as([*]const u8, @ptrFromInt(addr_a));
            const base_b = @as([*]const u8, @ptrFromInt(addr_b));
            const kind_a = base_a[0];
            const kind_b = base_b[0];
            if (kind_a != kind_b) return false;
            if (kind_a == gc_mod.STRING_KIND) {
                const len_a = std.mem.readInt(u32, base_a[4..8], .little);
                const len_b = std.mem.readInt(u32, base_b[4..8], .little);
                if (len_a != len_b) return false;
                return std.mem.eql(u8, base_a[8 .. 8 + len_a], base_b[8 .. 8 + len_b]);
            }
            if (kind_a == gc_mod.FLOAT_KIND) {
                const fa = @as(*const f64, @alignCast(@ptrCast(base_a + gc_mod.FLOAT_HEADER))).*;
                const fb = @as(*const f64, @alignCast(@ptrCast(base_b + gc_mod.FLOAT_HEADER))).*;
                return fa == fb;
            }
            if (kind_a == gc_mod.RECORD_KIND) {
                const fc_a = std.mem.readInt(u32, base_a[12..16], .little);
                const fc_b = std.mem.readInt(u32, base_b[12..16], .little);
                if (fc_a != fc_b) return false;
                const fields_a = @as([*]const Value, @alignCast(@ptrCast(base_a + gc_mod.RECORD_HEADER)));
                const fields_b = @as([*]const Value, @alignCast(@ptrCast(base_b + gc_mod.RECORD_HEADER)));
                var i: usize = 0;
                while (i < fc_a) : (i += 1) {
                    if (!deepEqual(fields_a[i], fields_b[i])) return false;
                }
                return true;
            }
            if (kind_a == gc_mod.ADT_KIND) {
                const adt_id_a = std.mem.readInt(u32, base_a[8..12], .little);
                const adt_id_b = std.mem.readInt(u32, base_b[8..12], .little);
                if (adt_id_a != adt_id_b) return false;
                const ctor_a = std.mem.readInt(u32, base_a[12..16], .little);
                const ctor_b = std.mem.readInt(u32, base_b[12..16], .little);
                if (ctor_a != ctor_b) return false;
                const arity_a = std.mem.readInt(u32, base_a[16..20], .little);
                const arity_b = std.mem.readInt(u32, base_b[16..20], .little);
                if (arity_a != arity_b) return false;
                const payloads_a = @as([*]const Value, @alignCast(@ptrCast(base_a + gc_mod.ADT_HEADER)));
                const payloads_b = @as([*]const Value, @alignCast(@ptrCast(base_b + gc_mod.ADT_HEADER)));
                var i: usize = 0;
                while (i < arity_a) : (i += 1) {
                    if (!deepEqual(payloads_a[i], payloads_b[i])) return false;
                }
                return true;
            }
            return false;
        },
        else => return false,
    }
}

/// Map a single Unicode code point to its simple uppercase (ASCII + Latin-1 Supplement + subset of Latin Extended-A). Returns c unchanged if no mapping.
fn utf8ToUpper(c: u21) u21 {
    if (c < 0x80) return @as(u21, std.ascii.toUpper(@as(u8, @intCast(c))));
    return latinUpper(c) orelse c;
}

/// Simple uppercase for Latin-1 Supplement (U+00E0–U+00FF) and common Latin Extended-A. ß (00DF) maps to same (no SS expansion).
fn latinUpper(c: u21) ?u21 {
    return switch (c) {
        0x00E0 => 0x00C0,
        0x00E1 => 0x00C1,
        0x00E2 => 0x00C2,
        0x00E3 => 0x00C3,
        0x00E4 => 0x00C4,
        0x00E5 => 0x00C5,
        0x00E6 => 0x00C6,
        0x00E7 => 0x00C7,
        0x00E8 => 0x00C8,
        0x00E9 => 0x00C9,
        0x00EA => 0x00CA,
        0x00EB => 0x00CB,
        0x00EC => 0x00CC,
        0x00ED => 0x00CD,
        0x00EE => 0x00CE,
        0x00EF => 0x00CF,
        0x00F0 => 0x00D0,
        0x00F1 => 0x00D1,
        0x00F2 => 0x00D2,
        0x00F3 => 0x00D3,
        0x00F4 => 0x00D4,
        0x00F5 => 0x00D5,
        0x00F6 => 0x00D6,
        0x00F8 => 0x00D8,
        0x00F9 => 0x00D9,
        0x00FA => 0x00DA,
        0x00FB => 0x00DB,
        0x00FC => 0x00DC,
        0x00FD => 0x00DD,
        0x00FE => 0x00DE,
        0x00FF => 0x0178,
        // Latin Extended-A (common)
        0x0101 => 0x0100,
        0x0103 => 0x0102,
        0x0105 => 0x0104,
        0x0107 => 0x0106,
        0x0109 => 0x0108,
        0x010B => 0x010A,
        0x010D => 0x010C,
        0x010F => 0x010E,
        0x0111 => 0x0110,
        0x0113 => 0x0112,
        0x0115 => 0x0114,
        0x0117 => 0x0116,
        0x0119 => 0x0118,
        0x011B => 0x011A,
        0x011D => 0x011C,
        0x011F => 0x011E,
        0x0121 => 0x0120,
        0x0123 => 0x0122,
        0x0125 => 0x0124,
        0x0127 => 0x0126,
        0x0129 => 0x0128,
        0x012B => 0x012A,
        0x012D => 0x012C,
        0x012F => 0x012E,
        0x0131 => 0x0049, // dotless i -> I
        0x0133 => 0x0132,
        0x0135 => 0x0134,
        0x0137 => 0x0136,
        0x013A => 0x0139,
        0x013C => 0x013B,
        0x013E => 0x013D,
        0x0140 => 0x013F,
        0x0142 => 0x0141,
        0x0144 => 0x0143,
        0x0146 => 0x0145,
        0x0148 => 0x0147,
        0x014B => 0x014A,
        0x014D => 0x014C,
        0x014F => 0x014E,
        0x0151 => 0x0150,
        0x0153 => 0x0152,
        0x0155 => 0x0154,
        0x0157 => 0x0156,
        0x0159 => 0x0158,
        0x015B => 0x015A,
        0x015D => 0x015C,
        0x015F => 0x015E,
        0x0161 => 0x0160,
        0x0163 => 0x0162,
        0x0165 => 0x0164,
        0x0167 => 0x0166,
        0x0169 => 0x0168,
        0x016B => 0x016A,
        0x016D => 0x016C,
        0x016F => 0x016E,
        0x0171 => 0x0170,
        0x0173 => 0x0172,
        0x0175 => 0x0174,
        0x0177 => 0x0176,
        0x017A => 0x0179,
        0x017C => 0x017B,
        0x017E => 0x017D,
        0x017F => 0x0053, // ſ -> S
        else => null,
    };
}

/// (String) -> String: uppercase copy. ASCII via std.ascii; Latin-1 Supplement and Latin Extended-A via table; rest unchanged.
pub fn stringUpper(gc: *GC, s_val: Value) Value {
    const s = getStringSlice(s_val) orelse return Value.ptr(0);
    var out = std.ArrayList(u8).initCapacity(page_alloc, s.len * 2) catch return Value.ptr(0); // may grow for some mappings
    defer out.deinit(page_alloc);
    const view = std.unicode.Utf8View.init(s) catch {
        // Invalid UTF-8: fall back to byte-at-a-time ASCII upper
        for (s) |c| {
            const up = if (c >= 'a' and c <= 'z') c - 32 else c;
            out.append(page_alloc, up) catch return Value.ptr(0);
        }
        return allocString(gc, out.items) catch Value.ptr(0);
    };
    var iter = view.iterator();
    while (iter.nextCodepoint()) |c| {
        const upper = utf8ToUpper(c);
        var buf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(upper, &buf) catch 1;
        out.appendSlice(page_alloc, buf[0..n]) catch return Value.ptr(0);
    }
    return allocString(gc, out.items) catch Value.ptr(0);
}

// --- Process/FS primitives ---

fn allocRecord(gc: *GC, module_index: u32, shape_id: u32, fields: []const Value) !Value {
    const total = gc_mod.RECORD_HEADER + fields.len * 8;
    const mem = try gc.allocObject(total);
    @memset(mem, 0);
    mem[0] = gc_mod.RECORD_KIND;
    std.mem.writeInt(u32, mem[4..8], module_index, .little);
    std.mem.writeInt(u32, mem[8..12], shape_id, .little);
    std.mem.writeInt(u32, mem[12..16], @as(u32, @intCast(fields.len)), .little);
    const fld = @as([*]Value, @alignCast(@ptrCast(mem.ptr + gc_mod.RECORD_HEADER)));
    for (fields, 0..) |v, i| {
        fld[i] = v;
    }
    return Value.ptr(@intFromPtr(mem.ptr));
}

/// Build a List<T> from a Zig slice (constructs Cons/Nil chain). module_index 0 is usually the entry module.
fn allocList(gc: *GC, items: []const Value) !Value {
    var tail = try allocListAdt(gc, 0, LIST_NIL, null, null);
    var i = items.len;
    while (i > 0) {
        i -= 1;
        tail = try allocListAdt(gc, 0, LIST_CONS, items[i], tail);
    }
    return tail;
}

/// () -> Record { os, args, env, cwd } using current_module.shapes[0] and shapes[1].
pub fn getProcess(gc: *GC, current_module: *const load_mod.Module) Value {
    const module_index = current_module.module_index;

    const os_str = comptime switch (@import("builtin").os.tag) {
        .macos => "darwin",
        .linux => "linux",
        .windows => "windows",
        else => "unknown",
    };
    const os_val = allocString(gc, os_str) catch return Value.unit();

    // args
    const raw_args = std.process.argsAlloc(page_alloc) catch return Value.unit();
    defer std.process.argsFree(page_alloc, raw_args);
    var arg_vals = std.ArrayList(Value).initCapacity(page_alloc, raw_args.len) catch return Value.unit();
    defer arg_vals.deinit(page_alloc);
    for (raw_args) |a| {
        const s = allocString(gc, a) catch return Value.unit();
        arg_vals.append(page_alloc, s) catch return Value.unit();
    }
    const args_list = allocList(gc, arg_vals.items) catch return Value.unit();

    // env
    const env_shape_id: u32 = if (current_module.shapes.len > 1) 1 else 0;
    var env_vals = std.ArrayList(Value).initCapacity(page_alloc, 64) catch return Value.unit();
    defer env_vals.deinit(page_alloc);
    {
        const env_ptr = std.c.environ;
        var idx: usize = 0;
        while (env_ptr[idx]) |entry| : (idx += 1) {
            const entry_slice = std.mem.sliceTo(entry, 0);
            if (std.mem.indexOf(u8, entry_slice, "=")) |eq_pos| {
                const k = allocString(gc, entry_slice[0..eq_pos]) catch return Value.unit();
                const v = allocString(gc, entry_slice[eq_pos + 1 ..]) catch return Value.unit();
                const pair = allocRecord(gc, module_index, env_shape_id, &[_]Value{ k, v }) catch return Value.unit();
                env_vals.append(page_alloc, pair) catch return Value.unit();
            }
        }
    }
    const env_list = allocList(gc, env_vals.items) catch return Value.unit();

    // cwd
    var cwd_buf: [4096]u8 = undefined;
    const cwd_slice = std.posix.getcwd(&cwd_buf) catch "unknown";
    const cwd_val = allocString(gc, cwd_slice) catch return Value.unit();

    // Build 4-field record { os, args, env, cwd } using shapes[0]
    const proc_shape_id: u32 = 0;
    return allocRecord(gc, module_index, proc_shape_id, &[_]Value{ os_val, args_list, env_list, cwd_val }) catch Value.unit();
}

/// (String) -> List<String>: directory listing. Each entry is "fullpath\tfile" or "fullpath\tdir".
pub fn listDir(gc: *GC, path_val: Value) Value {
    const path_slice = getStringSlice(path_val) orelse return allocList(gc, &[_]Value{}) catch Value.unit();

    var dir = std.fs.cwd().openDir(path_slice, .{ .iterate = true }) catch
        return allocList(gc, &[_]Value{}) catch Value.unit();
    defer dir.close();

    var entries = std.ArrayList(Value).initCapacity(page_alloc, 64) catch return Value.unit();
    defer entries.deinit(page_alloc);

    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        const kind_str: []const u8 = if (entry.kind == .directory) "dir" else "file";
        const full = std.fmt.allocPrint(page_alloc, "{s}/{s}\t{s}", .{ path_slice, entry.name, kind_str }) catch continue;
        defer page_alloc.free(full);
        const s = allocString(gc, full) catch continue;
        entries.append(page_alloc, s) catch continue;
    }

    return allocList(gc, entries.items) catch Value.unit();
}

/// (String, String) -> Unit: write text content to a file.
pub fn writeText(path_val: Value, content_val: Value) void {
    const path_slice = getStringSlice(path_val) orelse return;
    const content_slice = getStringSlice(content_val) orelse return;
    const file = std.fs.cwd().createFile(path_slice, .{}) catch return;
    defer file.close();
    _ = file.writeAll(content_slice) catch {};
}

/// () -> String: current OS name.
pub fn getOs(gc: *GC) Value {
    const os_str = comptime switch (@import("builtin").os.tag) {
        .macos => "darwin",
        .linux => "linux",
        .windows => "windows",
        else => "unknown",
    };
    return allocString(gc, os_str) catch Value.ptr(0);
}

/// () -> List<String>: command-line arguments.
pub fn getArgs(gc: *GC) Value {
    const raw_args = std.process.argsAlloc(page_alloc) catch return Value.ptr(0);
    defer std.process.argsFree(page_alloc, raw_args);
    var arg_vals = std.ArrayList(Value).initCapacity(page_alloc, raw_args.len) catch return Value.ptr(0);
    defer arg_vals.deinit(page_alloc);
    for (raw_args) |a| {
        const s = allocString(gc, a) catch return Value.ptr(0);
        arg_vals.append(page_alloc, s) catch return Value.ptr(0);
    }
    return allocList(gc, arg_vals.items) catch Value.ptr(0);
}

/// () -> String: current working directory.
pub fn getCwd(gc: *GC) Value {
    var cwd_buf: [4096]u8 = undefined;
    const cwd_slice = std.posix.getcwd(&cwd_buf) catch "unknown";
    return allocString(gc, cwd_slice) catch Value.ptr(0);
}

/// (String, List<String>) -> Int: spawn process and wait, return exit code.
pub fn runProcess(prog_val: Value, args_val: Value) Value {
    const prog_slice = getStringSlice(prog_val) orelse return Value.int(1);

    var argv = std.ArrayList([]const u8).initCapacity(page_alloc, 16) catch return Value.int(1);
    defer argv.deinit(page_alloc);
    argv.append(page_alloc, prog_slice) catch return Value.int(1);

    // Walk the list ADT to extract argument strings
    var cur = args_val;
    while (cur.tag == .ptr) {
        const addr = Value.ptrTo(cur);
        if (addr == 0) break;
        const base = @as([*]const u8, @ptrFromInt(addr));
        if (base[0] != gc_mod.ADT_KIND) break;
        const ctor = std.mem.readInt(u32, base[12..16], .little);
        if (ctor == LIST_NIL) break;
        if (ctor != LIST_CONS) break;
        const payloads = @as([*]const Value, @alignCast(@ptrCast(base + gc_mod.ADT_HEADER)));
        const s = getStringSlice(payloads[0]) orelse break;
        argv.append(page_alloc, s) catch break;
        cur = payloads[1];
    }

    var child = std.process.Child.init(argv.items, page_alloc);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.stdin_behavior = .Inherit;
    child.spawn() catch return Value.int(1);
    const term = child.wait() catch return Value.int(1);
    return switch (term) {
        .Exited => |code| Value.int(@intCast(code)),
        else => Value.int(1),
    };
}
