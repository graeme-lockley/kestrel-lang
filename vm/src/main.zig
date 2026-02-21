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

    const module = try load_mod.load(allocator, path);
    defer allocator.free(module.code);
    defer {
        for (module.string_slices) |s| allocator.free(s);
        allocator.free(module.string_slices);
        allocator.free(module.constants);
    }
    defer if (module.functions.len > 0) allocator.free(module.functions);
    defer if (module.shapes.len > 0) allocator.free(module.shapes);
    defer if (module.strings.len > 0) allocator.free(module.strings);
    defer {
        if (module.import_specifiers.len > 0) {
            for (module.import_specifiers) |s| allocator.free(s);
            allocator.free(module.import_specifiers);
        }
    }
    defer if (module.imported_functions.len > 0) allocator.free(module.imported_functions);
    exec_mod.run(allocator, &module, path);
}

test "vm placeholder" {
    try std.testing.expect(true);
}
