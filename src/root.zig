const std = @import("std");
const testing = std.testing;

pub const DiffEncoder = @import("encoder.zig");

const INSERT_TAG: u8 = 0x01;
const COPY_TAG: u8 = 0x02;

pub fn encode(
    source: []const u8,
    target: []const u8,
    allocator: std.mem.Allocator,
) ![]const u8 {
    var diff_encoder = DiffEncoder.init(source, target);
    var patch = std.ArrayList(u8).init(allocator);
    var writer = patch.writer();

    while (diff_encoder.next()) |delta| {
        switch (delta) {
            .insert => |data| {
                try writer.writeByte(INSERT_TAG);
                try writer.writeInt(u64, data.len, .little);
                try writer.writeAll(data);
            },
            .copy => |details| {
                try writer.writeByte(COPY_TAG);
                try writer.writeInt(u64, details.start, .little);
                try writer.writeInt(u64, details.len, .little);
            },
        }
    }
    return patch.toOwnedSlice();
}
pub fn decode(
    source: []const u8,
    patch: []const u8,
    allocator: std.mem.Allocator,
) ![]const u8 {
    var target = std.ArrayList(u8).init(allocator);
    defer target.deinit();

    var stream = std.io.fixedBufferStream(patch);
    var reader = stream.reader().any();

    while (stream.pos < patch.len) {
        const tag = reader.readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };

        switch (tag) {
            INSERT_TAG => {
                const len = try reader.readInt(u64, .little);
                const data_start = stream.pos;
                const data_end = data_start + len;

                if (data_end < data_start or data_end > patch.len) {
                    return error.InvalidData;
                }

                try target.appendSlice(patch[data_start..data_end]);
                stream.pos = data_end;
            },
            COPY_TAG => {
                const start = try reader.readInt(u64, .little);
                const len = try reader.readInt(u64, .little);
                const end = start + len;

                if (end < start or end > source.len) {
                    return error.InvalidData;
                }
                try target.appendSlice(source[start..end]);
            },
            else => return error.InvalidData,
        }
    }

    return target.toOwnedSlice();
}


fn testEncodeDecode(
    allocator: std.mem.Allocator,
    source: []const u8,
    target: []const u8,
) !void {
    const patch = try encode(source, target, allocator);
    defer allocator.free(patch);

    const result = try decode(source, patch, allocator);
    defer allocator.free(result);

    try testing.expectEqualStrings(target, result);
}

test "encode and decode: complex case" {
    const source = "This is a test.";
    const target = "This was a test!";
    try testEncodeDecode(testing.allocator, source, target);
}

test "encode and decode: leading insert" {
    try testEncodeDecode(testing.allocator, "bc", "abc");
}

test "encode and decode: trailing insert" {
    try testEncodeDecode(testing.allocator, "ab", "abc");
}

test "encode and decode: middle insert" {
    try testEncodeDecode(testing.allocator, "ac", "abc");
}

test "encode and decode: simple deletion" {
    try testEncodeDecode(testing.allocator, "axbyc", "abc");
}

test "encode and decode: identical" {
    try testEncodeDecode(testing.allocator, "hello world", "hello world");
}

test "encode and decode: empty source" {
    try testEncodeDecode(testing.allocator, "", "new content");
}

test "encode and decode: empty target" {
    try testEncodeDecode(testing.allocator, "old content", "");
}

test "encode and decode: both empty" {
    try testEncodeDecode(testing.allocator, "", "");
}

test "decode: invalid tag" {
    const source = "some data";
    const invalid_patch = &.{ 99, 1, 2, 3 };
    try testing.expectError(error.InvalidData, decode(source, invalid_patch, testing.allocator));
}

test "decode: copy out of bounds" {
    const source = "short";
    var buffer: [1 + @sizeOf(u64) * 2]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const writer = stream.writer();

    try writer.writeByte(COPY_TAG);
    try writer.writeInt(u64, 0, .little);
    try writer.writeInt(u64, 10, .little);

    try testing.expectError(error.InvalidData, decode(source, stream.getWritten(), testing.allocator));
}

test "decode: truncated patch (missing insert data)" {
    const source = "any";
    var buffer: [1 + @sizeOf(u64) + 3]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const writer = stream.writer();

    try writer.writeByte(INSERT_TAG);
    try writer.writeInt(u64, 10, .little);
    try writer.writeAll("abc");

    try testing.expectError(error.InvalidData, decode(source, stream.getWritten(), testing.allocator));
}

test {
    _ = DiffEncoder;
}