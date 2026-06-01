const std = @import("std");
const lib = @import("zig_fuzzer_pdf");

// Replays a single file through the parser. Use it on corpus samples or
// on crash inputs the fuzzer writes out.
//   zig build run -- corpus/hello.bin
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;

    if (args.len < 2) {
        std.debug.print("usage: {s} <file>\n", .{args[0]});
        return;
    }

    const dir = std.Io.Dir.cwd();
    const bytes = try dir.readFileAlloc(io, args[1], arena, .limited(64 * 1024 * 1024));

    lib.parsePdfHeader(bytes) catch |err| {
        std.debug.print("parse error: {s} ({d} bytes)\n", .{ @errorName(err), bytes.len });
        return;
    };
    std.debug.print("parsed ok ({d} bytes)\n", .{bytes.len});
}
