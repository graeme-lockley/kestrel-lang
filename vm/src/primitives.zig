// Minimal VM primitives (Phase 5). Stdlib .ks calls these; VM dispatches CALL to primitive by name.
const std = @import("std");
const Value = @import("value.zig").Value;

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
