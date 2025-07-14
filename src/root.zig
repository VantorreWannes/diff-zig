//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const DiffEncoder = @import("encoder.zig");

test {
    _ = DiffEncoder;
}