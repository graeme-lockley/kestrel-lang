// Load .kbc file (spec 03). Header, string table, constant pool, code.
const std = @import("std");
const Value = @import("value.zig").Value;
const gc_mod = @import("gc.zig");

const KBC1_MAGIC: [4]u8 = .{ 0x4B, 0x42, 0x43, 0x31 };

pub const FnEntry = struct {
    code_offset: u32,
    arity: u32,
};

pub const ShapeEntry = struct {
    field_count: u32,
    /// Field names (string table slices) for formatting; length = field_count.
    field_names: []const []const u8,
};

/// One ADT definition (section 6): type name and constructor names for formatting.
pub const AdtEntry = struct {
    /// Type name (string table slice).
    name: []const u8,
    /// Constructor names in tag order; length = constructor_count.
    constructor_names: []const []const u8,
};

pub const StringEntry = struct {
    data: []const u8,
};

/// One entry in the imported function table (03 §6.6): CALL fn_id >= function_count resolves via this.
pub const ImportedFnEntry = struct {
    import_index: u32,
    function_index: u32,
};

/// Debug section (03 §8): code_offset → (file_index, line) for stack traces.
pub const DebugEntry = struct {
    code_offset: u32,
    file_index: u32,
    line: u32,
};

pub const Module = struct {
    code: []const u8,
    constants: []const Value,
    functions: []const FnEntry,
    shapes: []const ShapeEntry,
    /// ADT table (section 6) for constructor/type names when formatting.
    adts: []const AdtEntry,
    strings: []const StringEntry,
    /// Allocated string constant heap objects (tag-6); caller must free each then this slice.
    string_slices: []const []const u8,
    /// Allocated float constant heap objects (tag-1); caller must free each then this slice.
    float_objects: []const []u8,
    /// Import table (03 §6.5): specifier string for each dependency (index = import_index).
    import_specifiers: []const []const u8,
    /// Imported function table (03 §6.6); fn_id in [function_count, function_count + len) uses this.
    imported_functions: []const ImportedFnEntry,
    /// Module global slots (export var); init's STORE_LOCAL writes here; LOAD_GLOBAL reads. Caller must free.
    globals: []Value,
    /// Index in the VM's module cache; set by caller when the module is registered. Used for record/ADT formatting.
    module_index: u32 = 0,
    /// File buffer; string table and section data point into this. Freed in freeModule.
    file_data: []const u8,
    /// Debug section (03 §8): file paths for debug_entries file_index. Caller must free each then this slice.
    debug_files: []const []const u8,
    /// Debug section: entries sorted by code_offset ascending for binary search.
    debug_entries: []const DebugEntry,
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

    // First pass: count string constants (tag 6) and float constants (tag 1)
    var string_count: usize = 0;
    var float_count: usize = 0;
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
                1 => {
                    float_count += 1;
                    entry_size = 12;
                },
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

    const float_objects = try allocator.alloc([]u8, float_count);
    errdefer allocator.free(float_objects);
    var float_idx: usize = 0;
    errdefer for (float_objects[0..float_idx]) |f| allocator.free(f);

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
                1 => {
                    if (o + 8 > data.len) return error.InvalidKbc;
                    const f64_val: f64 = @bitCast(std.mem.readInt(u64, data[o..][0..8], .little));
                    const float_block = try allocator.alloc(u8, 16);
                    float_block[0] = gc_mod.FLOAT_KIND;
                    float_block[1] = 0;
                    @as(*f64, @alignCast(@ptrCast(float_block[gc_mod.FLOAT_HEADER..].ptr))).* = f64_val;
                    float_objects[float_idx] = float_block;
                    float_idx += 1;
                    out.* = Value.ptr(@intFromPtr(float_block.ptr));
                    entry_size = 12;
                },
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
            const min_locals = 128;
            const alloc_size = if (n_globals > min_locals) n_globals else min_locals;
            globals = try allocator.alloc(Value, alloc_size);
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

    const s4_start = section_offsets[4];
    const s4_end = if (data.len > section_offsets[5]) section_offsets[5] else data.len;
    var debug_files: []const []const u8 = &[_][]const u8{};
    var debug_entries: []const DebugEntry = &[_]DebugEntry{};
    if (s4_start + 4 <= s4_end) {
        const file_count = std.mem.readInt(u32, data[s4_start..][0..4], .little);
        var o: usize = s4_start + 4;
        if (file_count > 0) {
            const debug_files_list = try allocator.alloc([]const u8, file_count);
            errdefer allocator.free(debug_files_list);
            for (debug_files_list) |*file_slot| {
                if (o + 4 > s4_end) return error.InvalidKbc;
                const str_idx = std.mem.readInt(u32, data[o..][0..4], .little);
                o += 4;
                file_slot.* = if (str_idx < strings.len) try allocator.dupe(u8, strings[str_idx].data) else &[_]u8{};
                errdefer allocator.free(file_slot.*);
            }
            debug_files = debug_files_list;
        } else {
            o += file_count * 4;
        }
        if (o + 4 > s4_end) return error.InvalidKbc;
        const entry_count = std.mem.readInt(u32, data[o..][0..4], .little);
        o += 4;
        if (entry_count > 0) {
            const entries_list = try allocator.alloc(DebugEntry, entry_count);
            errdefer allocator.free(entries_list);
            for (entries_list) |*e| {
                if (o + 12 > s4_end) return error.InvalidKbc;
                e.code_offset = std.mem.readInt(u32, data[o..][0..4], .little);
                e.file_index = std.mem.readInt(u32, data[o + 4..][0..4], .little);
                e.line = std.mem.readInt(u32, data[o + 8..][0..4], .little);
                o += 12;
            }
            debug_entries = entries_list;
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
            o += 4;
            const names_buf = try allocator.alloc([]const u8, s.field_count);
            errdefer allocator.free(names_buf);
            for (names_buf) |*name_slot| {
                if (o + 8 > data.len) return error.InvalidKbc;
                const name_index = std.mem.readInt(u32, data[o..][0..4], .little);
                o += 8; // name_index, type_index
                name_slot.* = if (name_index < strings.len) strings[name_index].data else &[_]u8{};
            }
            s.field_names = names_buf;
            o = align4(o);
        }
        shapes = shape_list;
    }

    const s6_start = section_offsets[6];
    const s6_end = data.len;
    var adts: []const AdtEntry = &[_]AdtEntry{};
    if (s6_start + 4 <= s6_end) {
        const adt_count = std.mem.readInt(u32, data[s6_start..][0..4], .little);
        const adt_list = try allocator.alloc(AdtEntry, adt_count);
        errdefer allocator.free(adt_list);
        var o: usize = s6_start + 4;
        for (adt_list) |*a| {
            o = align4(o);
            if (o + 8 > data.len) return error.InvalidKbc;
            const name_index = std.mem.readInt(u32, data[o..][0..4], .little);
            const constructor_count = std.mem.readInt(u32, data[o + 4..][0..4], .little);
            o += 8;
            a.name = if (name_index < strings.len) strings[name_index].data else &[_]u8{};
            const ctor_names_buf = try allocator.alloc([]const u8, constructor_count);
            errdefer allocator.free(ctor_names_buf);
            var c: usize = 0;
            while (c < constructor_count) : (c += 1) {
                if (o + 8 > data.len) return error.InvalidKbc;
                const ctor_name_index = std.mem.readInt(u32, data[o..][0..4], .little);
                o += 8; // name_index, payload_type_index
                ctor_names_buf[c] = if (ctor_name_index < strings.len) strings[ctor_name_index].data else &[_]u8{};
            }
            a.constructor_names = ctor_names_buf;
            o = align4(o);
        }
        adts = adt_list;
    }

    return .{
        .code = code,
        .constants = constants,
        .functions = functions,
        .shapes = shapes,
        .adts = adts,
        .strings = strings,
        .string_slices = string_slices,
        .float_objects = float_objects,
        .import_specifiers = import_specifiers,
        .imported_functions = imported_functions,
        .globals = globals,
        .file_data = data,
        .debug_files = debug_files,
        .debug_entries = debug_entries,
    };
}

/// Free all allocator-owned memory in a Module. Call after use when the module was loaded with load().
pub fn freeModule(allocator: std.mem.Allocator, m: *const Module) void {
    allocator.free(m.file_data);
    allocator.free(m.code);
    allocator.free(m.constants);
    for (m.string_slices) |s| allocator.free(s);
    allocator.free(m.string_slices);
    for (m.float_objects) |f| allocator.free(f);
    allocator.free(m.float_objects);
    if (m.functions.len > 0) allocator.free(m.functions);
    for (m.shapes) |s| allocator.free(s.field_names);
    if (m.shapes.len > 0) allocator.free(m.shapes);
    for (m.adts) |a| allocator.free(a.constructor_names);
    if (m.adts.len > 0) allocator.free(m.adts);
    if (m.strings.len > 0) allocator.free(m.strings);
    if (m.import_specifiers.len > 0) {
        for (m.import_specifiers) |s| allocator.free(s);
        allocator.free(m.import_specifiers);
    }
    if (m.imported_functions.len > 0) allocator.free(m.imported_functions);
    if (m.globals.len > 0) allocator.free(m.globals);
    if (m.debug_files.len > 0) {
        for (m.debug_files) |f| allocator.free(f);
        allocator.free(m.debug_files);
    }
    if (m.debug_entries.len > 0) allocator.free(m.debug_entries);
}

test "load minimal kbc" {
    const a = std.testing.allocator;
    const m = try load(a, "test/fixtures/empty.kbc");
    defer a.free(m.file_data);
    defer a.free(m.code);
    defer a.free(m.constants);
    defer {
        for (m.string_slices) |s| a.free(s);
        a.free(m.string_slices);
    }
    defer {
        for (m.float_objects) |f| a.free(f);
        a.free(m.float_objects);
    }
    if (m.functions.len > 0) a.free(m.functions);
    for (m.shapes) |s| a.free(s.field_names);
    if (m.shapes.len > 0) a.free(m.shapes);
    for (m.adts) |ad| a.free(ad.constructor_names);
    if (m.adts.len > 0) a.free(m.adts);
    if (m.import_specifiers.len > 0) a.free(m.import_specifiers);
    if (m.imported_functions.len > 0) a.free(m.imported_functions);
    if (m.globals.len > 0) a.free(m.globals);
    if (m.debug_files.len > 0) {
        for (m.debug_files) |f| a.free(f);
        a.free(m.debug_files);
    }
    if (m.debug_entries.len > 0) a.free(m.debug_entries);
    try std.testing.expect(m.code.len >= 1);
    try std.testing.expect(m.code[0] == 0x11);
    try std.testing.expect(m.debug_files.len == 0);
    try std.testing.expect(m.debug_entries.len == 0);
}
