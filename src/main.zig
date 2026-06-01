const std = @import("std");
const lib = @import("zig_fuzzer_pdf");

// Replays a single file through the parser. Use it on corpus samples or
// on crash inputs the fuzzer writes out.
//   zig build run -- corpus/seed01.bin
pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("usage: {s} <file>\n", .{args[0]});
        return;
    }

    const file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();
    const bytes = try file.readToEndAlloc(allocator, 64 * 1024 * 1024);
    defer allocator.free(bytes);

    lib.parsePdfHeader(bytes) catch |err| {
        std.debug.print("parse error: {s} ({d} bytes)\n", .{ @errorName(err), bytes.len });
        return;
    };
    std.debug.print("parsed ok ({d} bytes)\n", .{bytes.len});
}
