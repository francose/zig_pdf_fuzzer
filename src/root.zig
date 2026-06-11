const std = @import("std");
const parser = @import("parser.zig");

pub const parsePdfHeader = parser.parsePdfHeader;

const Stats = struct {
    ok: usize = 0,
    bad_magic: usize = 0,
    bad_version: usize = 0,
    truncated: usize = 0,
    saved: usize = 0,

    fn print(self: Stats, iterations: usize, elapsed_ns: u64) void {
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const rate = @as(f64, @floatFromInt(iterations)) / elapsed_s;
        std.debug.print("\n--- fuzz stats ---\n", .{});
        std.debug.print("iterations: {d}\n", .{iterations});
        std.debug.print("elapsed:    {d:.2}s ({d:.0} it/s)\n", .{ elapsed_s, rate });
        std.debug.print("ok:         {d}\n", .{self.ok});
        std.debug.print("BadMagic:   {d}\n", .{self.bad_magic});
        std.debug.print("BadVersion: {d}\n", .{self.bad_version});
        std.debug.print("Truncated:  {d}\n", .{self.truncated});
        std.debug.print("saved:      {d}\n", .{self.saved});
    }
};

// Writes an input we'd want to replay (parser got past the magic check
// but failed deeper) to crashes/<hash>.bin. Dedup'd by content hash so
// the same byte sequence doesn't get written twice. Returns true only
// when a new file was actually written.
fn saveInteresting(input: []const u8) !bool {
    var h = std.hash.Wyhash.init(0);
    h.update(input);
    const digest = h.final();

    var dir = try std.fs.cwd().makeOpenPath("crashes", .{});
    defer dir.close();

    var name_buf: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buf, "{x:0>16}.bin", .{digest});

    if (dir.access(name, .{})) |_| {
        return false;
    } else |_| {}

    const file = try dir.createFile(name, .{ .truncate = true });
    defer file.close();
    try file.writeAll(input);
    return true;
}

// Hand-rolled random fuzzer. Coverage-blind but it doesn't need Zig's
// experimental --fuzz mode (which is broken in both 0.15 and 0.16 right
// now). One million inputs per run. Half are prefix-biased with "%PDF-"
// so the deeper parser logic gets exercised — otherwise ~99% of random
// inputs die at BadMagic. Inputs that get past the magic check and fail
// deeper are saved to crashes/ as replay seeds, capped at 64 per run.
test "fuzz parsePdfHeader" {
    const iterations: usize = 1_000_000;
    const seed: u64 = 0xC0FFEE;
    const save_cap: usize = 64;

    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var buf: [4096]u8 = undefined;

    var stats: Stats = .{};
    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const len = rng.uintLessThan(usize, buf.len + 1);
        rng.bytes(buf[0..len]);

        // Bias half the iterations to start with the PDF magic so we
        // actually exercise version / obj_count / length parsing.
        if (i % 2 == 0 and len >= 5) {
            @memcpy(buf[0..5], "%PDF-");
        }

        const input = buf[0..len];
        if (parsePdfHeader(input)) {
            stats.ok += 1;
        } else |err| switch (err) {
            error.BadMagic => stats.bad_magic += 1,
            error.BadVersion => {
                stats.bad_version += 1;
                if (stats.saved < save_cap) {
                    if (saveInteresting(input)) |wrote| {
                        if (wrote) stats.saved += 1;
                    } else |_| {}
                }
            },
            error.Truncated => {
                stats.truncated += 1;
                if (stats.saved < save_cap) {
                    if (saveInteresting(input)) |wrote| {
                        if (wrote) stats.saved += 1;
                    } else |_| {}
                }
            },
        }
    }

    const elapsed_ns: u64 = @intCast(std.time.nanoTimestamp() - start);
    stats.print(iterations, elapsed_ns);
}
