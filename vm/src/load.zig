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

pub const Module = struct {
    code: []const u8,
    constants: []const Value,
    functions: []const FnEntry,
    shapes: []const ShapeEntry,
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
                6 => { entry_size = 8; out.* = Value.unit(); },
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
    };
}

test "load minimal kbc" {
    const a = std.testing.allocator;
    const m = try load(a, "test/fixtures/empty.kbc");
    defer a.free(m.code);
    defer a.free(m.constants);
    if (m.functions.len > 0) a.free(m.functions);
    if (m.shapes.len > 0) a.free(m.shapes);
    try std.testing.expect(m.code.len >= 1);
    try std.testing.expect(m.code[0] == 0x11);
}
