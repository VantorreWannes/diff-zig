//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const testing = std.testing;
pub const DiffEncoder = @import("encoder.zig");

const INSERT_TAG: u8 = 0x01;
const COPY_TAG: u8 = 0x02;
const BUFFER_SIZE = 64 * 1024;

pub fn encode(writer: std.io.AnyWriter, source_reader: std.io.AnyReader, target_reader: std.io.AnyReader) !void {
    var source_buffer: [BUFFER_SIZE]u8 = undefined;
    var target_buffer: [BUFFER_SIZE]u8 = undefined;

    var source_bytes_read = try source_reader.read(&source_buffer);
    var target_bytes_read = try target_reader.read(&target_buffer);

    while (target_bytes_read > 0) {
        const source = source_buffer[0..source_bytes_read];
        const target = target_buffer[0..target_bytes_read];

        var diff_encoder = DiffEncoder.init(source, target);

        while (diff_encoder.next()) |delta| {
            switch (delta) {
                .insert => |data| {
                    try writer.writeByte(INSERT_TAG);
                    try std.leb.writeUleb128(writer, data.len);
                    try writer.writeAll(data);
                },
                .copy => |details| {
                    try writer.writeByte(COPY_TAG);
                    try std.leb.writeUleb128(writer, details.start);
                    try std.leb.writeUleb128(writer, details.len);
                },
            }
        }

        source_bytes_read = try source_reader.read(&source_buffer);
        target_bytes_read = try target_reader.read(&target_buffer);
    }
}

fn testEncode(allocator: std.mem.Allocator, source_data: []const u8, target_data: []const u8, expected_output: []const u8) !void {
    var source_stream = std.io.fixedBufferStream(source_data);
    var target_stream = std.io.fixedBufferStream(target_data);

    var output_list = std.ArrayList(u8).init(allocator);
    defer output_list.deinit();

    const writer = output_list.writer().any();
    const source_reader = source_stream.reader().any();
    const target_reader = target_stream.reader().any();

    try encode(writer, source_reader, target_reader);

    try testing.expectEqualSlices(u8, expected_output, output_list.items);
}

test "encode with empty source" {
    const allocator = std.testing.allocator;
    const source = "";
    const target = "new data";
    const expected = &[_]u8{
        INSERT_TAG,
        8,
        'n',
        'e',
        'w',
        ' ',
        'd',
        'a',
        't',
        'a',
    };
    try testEncode(allocator, source, target, expected);
}

test "encode with empty target" {
    const allocator = std.testing.allocator;
    const source = "some data";
    const target = "";
    const expected = &[_]u8{};
    try testEncode(allocator, source, target, expected);
}

test "encode with identical data" {
    const allocator = std.testing.allocator;
    const data = "hello world";
    const expected = &[_]u8{
        COPY_TAG,
        0,
        11,
    };
    try testEncode(allocator, data, data, expected);
}

test "encode with middle insert" {
    const allocator = std.testing.allocator;
    const source = "ac";
    const target = "abc";
    const expected = &[_]u8{ COPY_TAG, 0, 1, INSERT_TAG, 1, 'b', COPY_TAG, 1, 1 };
    try testEncode(allocator, source, target, expected);
}

test "encode with simple deletion" {
    const allocator = std.testing.allocator;
    const source = "axbyc";
    const target = "abc";
    const expected = &[_]u8{ COPY_TAG, 0, 1, COPY_TAG, 2, 1, COPY_TAG, 4, 1 };
    try testEncode(allocator, source, target, expected);
}

test {
    _ = DiffEncoder;
}
