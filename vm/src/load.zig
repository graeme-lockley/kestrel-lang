// Load .kbc file (spec 03). Header, string table, constant pool, code.
const std = @import("std");
const Value = @import("value.zig").Value;

const KBC1_MAGIC: [4]u8 = .{ 0x4B, 0x42, 0x43, 0x31 };

pub const FnEntry = struct {
    code_offset: u32,
    arity: u32,
};

pub const ShapeEntry = struct {
    field_count: u32,
};

pub const StringEntry = struct {
    data: []const u8,
};

/// One entry in the imported function table (03 §6.6): CALL fn_id >= function_count resolves via this.
pub const ImportedFnEntry = struct {
    import_index: u32,
    function_index: u32,
};

pub const Module = struct {
    code: []const u8,
    constants: []const Value,
    functions: []const FnEntry,
    shapes: []const ShapeEntry,
    strings: []const StringEntry,
    /// Allocated string constant heap objects (tag-6); caller must free each then this slice.
    string_slices: []const []const u8,
    /// Import table (03 §6.5): specifier string for each dependency (index = import_index).
    import_specifiers: []const []const u8,
    /// Imported function table (03 §6.6); fn_id in [function_count, function_count + len) uses this.
    imported_functions: []const ImportedFnEntry,
    /// Module global slots (export var); init's STORE_LOCAL writes here; LOAD_GLOBAL reads. Caller must free.
    globals: []Value,
};

fn align4(n: usize) usize {
    return (n + 3) & ~@as(usize, 3);
}

pub fn load(allocator: std.mem.Allocator, path: []const u8) !Module {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    errdefer allocator.free(data);

    if (data.len < 36) return error.InvalidKbc;
    if (!std.mem.eql(u8, data[0..4], &KBC1_MAGIC)) return error.InvalidMagic;
    const version = std.mem.readInt(u32, data[4..8], .little);
    if (version != 1) return error.UnsupportedVersion;

    const section_offsets: [7]u32 = .{
        std.mem.readInt(u32, data[8..12], .little),
        std.mem.readInt(u32, data[12..16], .little),
        std.mem.readInt(u32, data[16..20], .little),
        std.mem.readInt(u32, data[20..24], .little),
        std.mem.readInt(u32, data[24..28], .little),
        std.mem.readInt(u32, data[28..32], .little),
        std.mem.readInt(u32, data[32..36], .little),
    };

    // Load string table (section 0)
    const s0_start = section_offsets[0];
    const s0_end = if (data.len > section_offsets[1]) section_offsets[1] else data.len;
    var strings: []const StringEntry = &[_]StringEntry{};
    if (s0_start + 4 <= s0_end) {
        const str_count = std.mem.readInt(u32, data[s0_start..][0..4], .little);
        const str_list = try allocator.alloc(StringEntry, str_count);
        errdefer allocator.free(str_list);
        var o: usize = s0_start + 4;
        for (str_list) |*entry| {
            o = align4(o);
            if (o + 4 > s0_end) return error.InvalidKbc;
            const len = std.mem.readInt(u32, data[o..][0..4], .little);
            o += 4;
            if (o + len > s0_end) return error.InvalidKbc;
            entry.data = data[o..o+len];
            o += len;
        }
        strings = str_list;
    }

    const code_start = section_offsets[3];
    const code_end = if (data.len > section_offsets[4]) section_offsets[4] else data.len;
    if (code_start >= data.len or code_end > data.len or code_start >= code_end) return error.InvalidKbc;

    const code = try allocator.dupe(u8, data[code_start..code_end]);

    const pool_start = section_offsets[1];
    const pool_count = if (pool_start + 4 <= data.len)
        std.mem.readInt(u32, data[pool_start..][0..4], .little)
    else
        0;
    const constants = try allocator.alloc(Value, pool_count);
    errdefer allocator.free(constants);

    // First pass: count string constants (tag 6)
    var string_count: usize = 0;
    if (pool_count > 0 and pool_start + 4 <= data.len) {
        var o: usize = pool_start + 4;
        for (constants) |_| {
            if (o + 4 > data.len) return error.InvalidKbc;
            o = align4(o);
            const entry_start = o;
            const tag = data[o];
            o += 4;
            var entry_size: usize = 4;
            switch (tag) {
                0 => entry_size = 12,
                1 => entry_size = 12,
                2, 3, 4 => {},
                5 => entry_size = 8,
                6 => {
                    string_count += 1;
                    if (o + 4 > data.len) return error.InvalidKbc;
                    const str_idx = std.mem.readInt(u32, data[o..][0..4], .little);
                    if (str_idx < strings.len) {
                        entry_size = 8;
                    }
                },
                else => {},
            }
            o = align4(entry_start + entry_size);
        }
    }

    const string_slices = try allocator.alloc([]const u8, string_count);
    errdefer allocator.free(string_slices);
    var string_idx: usize = 0;
    errdefer for (string_slices[0..string_idx]) |s| allocator.free(s);

    if (pool_count > 0 and pool_start + 4 <= data.len) {
        var o: usize = pool_start + 4;
        for (constants) |*out| {
            if (o + 4 > data.len) return error.InvalidKbc;
            o = align4(o);
            const entry_start = o;
            const tag = data[o];
            o += 4;
            var entry_size: usize = 4;
            switch (tag) {
                0 => {
                    if (o + 8 > data.len) return error.InvalidKbc;
                    out.* = Value.int(std.mem.readInt(i64, data[o..][0..8], .little));
                    entry_size = 12;
                },
                1 => { entry_size = 12; out.* = Value.unit(); },
                2 => { out.* = Value.boolVal(false); },
                3 => { out.* = Value.boolVal(true); },
                4 => { out.* = Value.unit(); },
                5 => {
                    if (o + 4 > data.len) return error.InvalidKbc;
                    out.* = Value.char(std.mem.readInt(u32, data[o..][0..4], .little));
                    entry_size = 8;
                },
                6 => {
                    if (o + 4 > data.len) return error.InvalidKbc;
                    const str_idx_val = std.mem.readInt(u32, data[o..][0..4], .little);
                    if (str_idx_val >= strings.len) return error.InvalidKbc;
                    const str_data = strings[str_idx_val].data;
                    const obj_size = 8 + str_data.len;
                    const obj = try allocator.alloc(u8, obj_size);
                    obj[0] = 4; // STRING_KIND
                    obj[1] = 0;
                    obj[2] = 0;
                    obj[3] = 0;
                    std.mem.writeInt(u32, obj[4..8], @as(u32, @intCast(str_data.len)), .little);
                    @memcpy(obj[8..8+str_data.len], str_data);
                    string_slices[string_idx] = obj;
                    string_idx += 1;
                    out.* = Value.ptr(@intFromPtr(obj.ptr));
                    entry_size = 8;
                },
                else => out.* = Value.unit(),
            }
            o = align4(entry_start + entry_size);
        }
    }

    const s2_start = section_offsets[2];
    var functions: []const FnEntry = &[_]FnEntry{};
    var import_specifiers: []const []const u8 = &[_][]const u8{};
    var imported_functions: []const ImportedFnEntry = &[_]ImportedFnEntry{};
    var globals: []Value = &[_]Value{};
    if (s2_start + 8 <= data.len) {
        const n_globals = std.mem.readInt(u32, data[s2_start..][0..4], .little);
        const fn_count = std.mem.readInt(u32, data[s2_start + 4 ..][0..4], .little);
        if (n_globals > 0) {
            globals = try allocator.alloc(Value, n_globals);
            for (globals) |*v| v.* = Value.unit();
        }
        const fns = try allocator.alloc(FnEntry, fn_count);
        errdefer allocator.free(fns);
        var o: usize = s2_start + 8; // after n_globals and fn_count
        for (fns) |*e| {
            if (o + 24 > data.len) return error.InvalidKbc;
            _ = std.mem.readInt(u32, data[o..][0..4], .little); // name_index
            e.arity = std.mem.readInt(u32, data[o + 4 ..][0..4], .little);
            e.code_offset = std.mem.readInt(u32, data[o + 8 ..][0..4], .little);
            o += 24;
        }
        functions = fns;

        // Skip 6.2 type table: type_count + (type_count+1)*4 + blob
        if (o + 4 > data.len) return error.InvalidKbc;
        const type_count = std.mem.readInt(u32, data[o..][0..4], .little);
        o += 4;
        if (o + (type_count + 1) * 4 > data.len) return error.InvalidKbc;
        const blob_len = std.mem.readInt(u32, data[o + type_count * 4 ..][0..4], .little);
        o += (type_count + 1) * 4 + blob_len;
        o = align4(o);

        // Skip 6.4 exported type declarations
        if (o + 4 > data.len) return error.InvalidKbc;
        const exported_type_count = std.mem.readInt(u32, data[o..][0..4], .little);
        o += 4 + exported_type_count * 8;

        // 6.5 Import table
        if (o + 4 > data.len) return error.InvalidKbc;
        const import_count = std.mem.readInt(u32, data[o..][0..4], .little);
        o += 4;
        const spec_list = try allocator.alloc([]const u8, import_count);
        errdefer allocator.free(spec_list);
        for (spec_list) |*spec_ptr| {
            if (o + 4 > data.len) return error.InvalidKbc;
            const str_idx = std.mem.readInt(u32, data[o..][0..4], .little);
            o += 4;
            if (str_idx < strings.len) {
                spec_ptr.* = try allocator.dupe(u8, strings[str_idx].data);
            } else {
                spec_ptr.* = &[_]u8{};
            }
        }
        import_specifiers = spec_list;

        // 6.6 Imported function table (only if still inside section 2)
        const s2_end = section_offsets[3];
        if (o + 4 <= data.len and o + 4 <= s2_end) {
            const imported_fn_count = std.mem.readInt(u32, data[o..][0..4], .little);
            o += 4;
            const imp_fns = try allocator.alloc(ImportedFnEntry, imported_fn_count);
            errdefer allocator.free(imp_fns);
            for (imp_fns) |*entry| {
                if (o + 8 > data.len) return error.InvalidKbc;
                entry.import_index = std.mem.readInt(u32, data[o..][0..4], .little);
                entry.function_index = std.mem.readInt(u32, data[o + 4 ..][0..4], .little);
                o += 8;
            }
            imported_functions = imp_fns;
        }
    }

    const s5_start = section_offsets[5];
    const s5_end = if (data.len > section_offsets[6]) section_offsets[6] else data.len;
    var shapes: []const ShapeEntry = &[_]ShapeEntry{};
    if (s5_start + 4 <= s5_end) {
        const shape_count = std.mem.readInt(u32, data[s5_start..][0..4], .little);
        const shape_list = try allocator.alloc(ShapeEntry, shape_count);
        errdefer allocator.free(shape_list);
        var o: usize = s5_start + 4;
        for (shape_list) |*s| {
            if (o + 4 > data.len) return error.InvalidKbc;
            o = align4(o);
            s.field_count = std.mem.readInt(u32, data[o..][0..4], .little);
            o += 4 + s.field_count * 8; // skip field_count pairs (name_index, type_index)
            o = align4(o);
        }
        shapes = shape_list;
    }

    allocator.free(data);
    return .{
        .code = code,
        .constants = constants,
        .functions = functions,
        .shapes = shapes,
        .strings = strings,
        .string_slices = string_slices,
        .import_specifiers = import_specifiers,
        .imported_functions = imported_functions,
        .globals = globals,
    };
}

/// Free all allocator-owned memory in a Module. Call after use when the module was loaded with load().
pub fn freeModule(allocator: std.mem.Allocator, m: *const Module) void {
    allocator.free(m.code);
    allocator.free(m.constants);
    for (m.string_slices) |s| allocator.free(s);
    allocator.free(m.string_slices);
    if (m.functions.len > 0) allocator.free(m.functions);
    if (m.shapes.len > 0) allocator.free(m.shapes);
    if (m.strings.len > 0) allocator.free(m.strings);
    if (m.import_specifiers.len > 0) {
        for (m.import_specifiers) |s| allocator.free(s);
        allocator.free(m.import_specifiers);
    }
    if (m.imported_functions.len > 0) allocator.free(m.imported_functions);
    if (m.globals.len > 0) allocator.free(m.globals);
}

test "load minimal kbc" {
    const a = std.testing.allocator;
    const m = try load(a, "test/fixtures/empty.kbc");
    defer a.free(m.code);
    defer a.free(m.constants);
    defer {
        for (m.string_slices) |s| a.free(s);
        a.free(m.string_slices);
    }
    if (m.functions.len > 0) a.free(m.functions);
    if (m.shapes.len > 0) a.free(m.shapes);
    if (m.import_specifiers.len > 0) a.free(m.import_specifiers);
    if (m.imported_functions.len > 0) a.free(m.imported_functions);
    if (m.globals.len > 0) a.free(m.globals);
    try std.testing.expect(m.code.len >= 1);
    try std.testing.expect(m.code[0] == 0x11);
}
