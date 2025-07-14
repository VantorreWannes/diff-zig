const std = @import("std");
const testing = std.testing;
const cos_lcs = @import("cos_lcs");
const CosLcsIterator = cos_lcs.CosLcsIterator;

const DiffEncoder = @This();

pub const CopyDetails = struct {
    start: usize,
    len: usize,
};

pub const Diff = union(enum) {
    copy: CopyDetails,
    insert: []const u8,
};

source: []const u8,
target: []const u8,
target_index: usize = 0,
lcs_iterator: CosLcsIterator,
next_pair: ?CosLcsIterator.Pair = null,

pub fn init(source: []const u8, target: []const u8) DiffEncoder {
    var lcs_iterator = CosLcsIterator.init(source, target);
    const next_pair = lcs_iterator.nextPair();
    return DiffEncoder{
        .source = source,
        .target = target,
        .lcs_iterator = lcs_iterator,
        .next_pair = next_pair,
    };
}

pub fn next(self: *DiffEncoder) ?Diff {
    if (self.target_index >= self.target.len) {
        return null;
    }

    const current_pair = self.next_pair;

    if (current_pair == null) {
        const insert_slice = self.target[self.target_index..];
        self.target_index = self.target.len;
        return Diff{ .insert = insert_slice };
    }
    const pair = current_pair.?;

    if (self.target_index < pair.target_index) {
        const insert_slice = self.target[self.target_index..pair.target_index];
        self.target_index = pair.target_index;
        return Diff{ .insert = insert_slice };
    }

    const start_source_index = pair.source_index;
    const start_target_index = pair.target_index;
    var len: usize = 1;

    while (self.lcs_iterator.nextPair()) |next_pair| {
        if (next_pair.source_index == start_source_index + len and
            next_pair.target_index == start_target_index + len)
        {
            len += 1;
        } else {
            self.next_pair = next_pair;
            break;
        }
    } else {
        self.next_pair = null;
    }

    const copy_details = CopyDetails{
        .start = start_source_index,
        .len = len,
    };

    self.target_index += len;

    return Diff{ .copy = copy_details };
}

test "empty source and target" {
    var encoder = DiffEncoder.init("", "");
    try testing.expectEqual(null, encoder.next());
}

test "empty target" {
    var encoder = DiffEncoder.init("abc", "");
    try testing.expectEqual(null, encoder.next());
}

test "empty source" {
    var encoder = DiffEncoder.init("", "abc");
    const diff = encoder.next().?;
    try testing.expect(std.mem.eql(u8, "abc", diff.insert));

    try testing.expectEqual(null, encoder.next());
}

test "identical source and target" {
    var encoder = DiffEncoder.init("abc", "abc");
    const diff = encoder.next().?;
    try testing.expectEqual(@as(usize, 0), diff.copy.start);
    try testing.expectEqual(@as(usize, 3), diff.copy.len);

    try testing.expectEqual(null, encoder.next());
}

test "leading insert" {
    var encoder = DiffEncoder.init("bc", "abc");
    var diff = encoder.next().?;
    try testing.expect(std.mem.eql(u8, "a", diff.insert));

    diff = encoder.next().?;
    try testing.expectEqual(@as(usize, 0), diff.copy.start);
    try testing.expectEqual(@as(usize, 2), diff.copy.len);

    try testing.expectEqual(null, encoder.next());
}

test "trailing insert" {
    var encoder = DiffEncoder.init("ab", "abc");
    var diff = encoder.next().?;
    try testing.expectEqual(@as(usize, 0), diff.copy.start);
    try testing.expectEqual(@as(usize, 2), diff.copy.len);

    diff = encoder.next().?;
    try testing.expect(std.mem.eql(u8, "c", diff.insert));

    try testing.expectEqual(null, encoder.next());
}

test "middle insert" {
    var encoder = DiffEncoder.init("ac", "abc");
    var diff = encoder.next().?;
    try testing.expectEqual(@as(usize, 0), diff.copy.start);
    try testing.expectEqual(@as(usize, 1), diff.copy.len);

    diff = encoder.next().?;
    try testing.expect(std.mem.eql(u8, "b", diff.insert));

    diff = encoder.next().?;
    try testing.expectEqual(@as(usize, 1), diff.copy.start);
    try testing.expectEqual(@as(usize, 1), diff.copy.len);

    try testing.expectEqual(null, encoder.next());
}

test "simple deletion (source has extra chars)" {
    var encoder = DiffEncoder.init("axbyc", "abc");
    var diff = encoder.next().?;
    try testing.expectEqual(@as(usize, 0), diff.copy.start);
    try testing.expectEqual(@as(usize, 1), diff.copy.len);

    diff = encoder.next().?;
    try testing.expectEqual(@as(usize, 2), diff.copy.start);
    try testing.expectEqual(@as(usize, 1), diff.copy.len);

    diff = encoder.next().?;
    try testing.expectEqual(@as(usize, 4), diff.copy.start);
    try testing.expectEqual(@as(usize, 1), diff.copy.len);

    try testing.expectEqual(null, encoder.next());
}

test "complex case with mixed operations" {
    const source = "This is a test.";
    const target = "This was a test!";

    var encoder = DiffEncoder.init(source, target);

    var diff = encoder.next().?;
    try testing.expectEqual(@as(usize, 0), diff.copy.start);
    try testing.expectEqual(@as(usize, 5), diff.copy.len);

    diff = encoder.next().?;
    try testing.expectEqualSlices(u8, "wa", diff.insert);

    diff = encoder.next().?;
    try testing.expectEqual(@as(usize, 6), diff.copy.start);
    try testing.expectEqual(@as(usize, 8), diff.copy.len);

    diff = encoder.next().?;
    try testing.expect(std.mem.eql(u8, "!", diff.insert));

    try testing.expectEqual(null, encoder.next());
}

test {
    _ = DiffEncoder;
}
