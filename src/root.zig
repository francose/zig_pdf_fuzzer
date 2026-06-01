const std = @import("std");
const parser = @import("parser.zig");

pub const parsePdfHeader = parser.parsePdfHeader;

// Day-one harness. The stub parser has deliberate OOB bugs so the fuzzer
// has something to find. Replace parser.zig with @cImport bindings to
// poppler / MuPDF once the workflow feels right.
test "fuzz parsePdfHeader" {
    try std.testing.fuzz({}, fuzzOne, .{});
}

fn fuzzOne(_: void, smith: *std.testing.Smith) !void {
    var buf: [4096]u8 = undefined;
    const len = smith.slice(&buf);
    parsePdfHeader(buf[0..len]) catch {};
}
