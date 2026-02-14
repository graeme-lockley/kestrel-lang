// Minimal VM primitives (Phase 5). Stdlib .ks calls these; VM dispatches CALL to primitive by name.
const std = @import("std");
const Value = @import("value.zig").Value;

/// Print a value to stdout
/// Handles integers, booleans, unit, and chars
pub fn print(val: Value) void {
    // Using a buffered writer for stdout
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();

    const output = switch (val.tag) {
        .int => std.fmt.allocPrint(allocator, "{d}\n", .{Value.intTo(val)}) catch return,
        .bool => std.fmt.allocPrint(allocator, "{}\n", .{val.payload != 0}) catch return,
        .unit => std.fmt.allocPrint(allocator, "()\n", .{}) catch return,
        .char => blk: {
            const c = @as(u21, @intCast(val.payload));
            var cbuf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(c, &cbuf) catch 1;
            break :blk std.fmt.allocPrint(allocator, "{s}\n", .{cbuf[0..len]}) catch return;
        },
        else => std.fmt.allocPrint(allocator, "<value>\n", .{}) catch return,
    };

    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    _ = stdout.write(output) catch {};
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
