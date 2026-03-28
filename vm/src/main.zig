// Kestrel VM — load and execute .kbc bytecode (spec 03, 04, 05).
const std = @import("std");
const load_mod = @import("load.zig");
const exec_mod = @import("exec.zig");
const value_mod = @import("value.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: kestrel <file.kbc>\n", .{});
        std.process.exit(1);
    }
    const path = args[1];
    _ = value_mod;

    var module = try load_mod.load(allocator, path);
    defer load_mod.freeModule(allocator, &module);
    if (!exec_mod.run(allocator, &module, path, null)) {
        std.process.exit(1);
    }
}

test {
    // Register tests from all VM modules (Zig only runs tests reachable from the root file).
    _ = @import("value.zig");
    _ = @import("load.zig");
    _ = @import("exec.zig");
    _ = @import("gc.zig");
    _ = @import("primitives.zig");
    _ = @import("vm_bytecode_tests.zig");
}
