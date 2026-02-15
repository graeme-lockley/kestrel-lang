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

pub const Module = struct {
    code: []const u8,
    constants: []const Value,
    functions: []const FnEntry,
    shapes: []const ShapeEntry,
    strings: []const StringEntry,
    /// Allocated string constant heap objects (tag-6); caller must free each then this slice.
    string_slices: []const []const u8,
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
    if (s2_start + 4 <= data.len) {
        const fn_count = std.mem.readInt(u32, data[s2_start..][0..4], .little);
        const fns = try allocator.alloc(FnEntry, fn_count);
        errdefer allocator.free(fns);
        var o: usize = s2_start + 4;
        for (fns) |*e| {
            if (o + 24 > data.len) return error.InvalidKbc;
            _ = std.mem.readInt(u32, data[o..][0..4], .little); // name_index
            e.arity = std.mem.readInt(u32, data[o + 4 ..][0..4], .little);
            e.code_offset = std.mem.readInt(u32, data[o + 8 ..][0..4], .little);
            o += 24;
        }
        functions = fns;
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
    };
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
    try std.testing.expect(m.code.len >= 1);
    try std.testing.expect(m.code[0] == 0x11);
}
