// Minimal VM primitives (Phase 5). Stdlib .ks calls these; VM dispatches CALL to primitive by name.
// Future: __write_stdout_string(s), __string_length, __json_parse/__json_stringify, __read_file_async, HTTP hooks.
const std = @import("std");
const Value = @import("value.zig").Value;

pub fn writeStdoutString(_: std.mem.Allocator, _: Value) void {
    // TODO: resolve string value (PTR to STRING heap), write UTF-8 to stdout
}
