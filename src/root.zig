const std = @import("std");
const parser = @import("parser.zig");
const mupdf = @import("mupdf.zig");
const poppler = @import("poppler.zig");
const crash = @import("crash_containment.zig");

pub const parsePdfHeader = parser.parsePdfHeader;
pub const mupdfOpenFromMemory = mupdf.openFromMemory;
pub const popplerOpenFromMemory = poppler.openFromMemory;
pub const MupdfResult = mupdf.Result;
pub const PopplerResult = poppler.Result;

test "crash containment recovers from a SIGSEGV" {
    crash.installHandlers();
    const outcome = crash.triggerSegv("anything");
    try std.testing.expectEqual(crash.Outcome.crashed, outcome);
    // if we got here the segv was caught. next parser call should still work.
    const after = crash.mupdfOpen("not a pdf");
    try std.testing.expectEqual(crash.Outcome.rejected, after);
}

test "mupdf rejects garbage" {
    const result = mupdf.openFromMemory("not a pdf, just some bytes");
    try std.testing.expectEqual(mupdf.Result.rejected, result);
}

test "poppler rejects garbage" {
    const result = poppler.openFromMemory("not a pdf, just some bytes");
    try std.testing.expectEqual(poppler.Result.rejected, result);
}

// inputs the two parsers disagreed on. dedup'd by hash.
fn saveDisagreement(input: []const u8) !void {
    var h = std.hash.Wyhash.init(0);
    h.update(input);
    const digest = h.final();

    var dir = try std.fs.cwd().makeOpenPath("disagreements", .{});
    defer dir.close();

    var name_buf: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buf, "{x:0>16}.bin", .{digest});
    if (dir.access(name, .{})) |_| return else |_| {}

    const file = try dir.createFile(name, .{ .truncate = true });
    defer file.close();
    try file.writeAll(input);
}

// 500 iters because real parsers are slow vs the stub. saves disagreements
// and any input that crashed either one.
test "fuzz differential mupdf vs poppler" {
    crash.installHandlers();

    const iterations: usize = 500;
    const seed: u64 = 0xD1FFFEED;

    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var buf: [256]u8 = undefined;

    var disagreements: usize = 0;
    var agreements_accept: usize = 0;
    var agreements_reject: usize = 0;
    var mupdf_crashes: usize = 0;
    var poppler_crashes: usize = 0;
    var errors: usize = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const len = rng.uintLessThan(usize, buf.len + 1);
        rng.bytes(buf[0..len]);
        if (len >= 5) @memcpy(buf[0..5], "%PDF-");

        const input = buf[0..len];
        const m = crash.mupdfOpen(input);
        const p = crash.popplerOpen(input);

        if (m == .crashed) {
            mupdf_crashes += 1;
            saveDisagreement(input) catch {};
            continue;
        }
        if (p == .crashed) {
            poppler_crashes += 1;
            saveDisagreement(input) catch {};
            continue;
        }
        if (m == .context_failure or p == .context_failure) {
            errors += 1;
            continue;
        }

        const m_ok = m == .parsed;
        const p_ok = p == .parsed;
        if (m_ok == p_ok) {
            if (m_ok) agreements_accept += 1 else agreements_reject += 1;
        } else {
            disagreements += 1;
            saveDisagreement(input) catch {};
        }
    }

    std.debug.print(
        \\
        \\--- differential stats ---
        \\iterations:      {d}
        \\both accepted:   {d}
        \\both rejected:   {d}
        \\disagreed:       {d}
        \\mupdf crashes:   {d}
        \\poppler crashes: {d}
        \\context errors:  {d}
        \\
    , .{
        iterations, agreements_accept, agreements_reject, disagreements,
        mupdf_crashes, poppler_crashes, errors,
    });
}

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

// inputs that got past the magic check and died deeper. dedup'd by hash.
// returns true only when a new file was written.
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

// 1M random inputs against the stub. zigs builtin --fuzz mode is broken in
// both 0.15 and 0.16 so the loop is hand rolled. tiered bias gives each
// parser branch real coverage. saves up to 64 near miss inputs per run.
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

        // tier 0: magic + valid version + small obj_count, hits the obj loop
        // tier 1: magic only, hits BadVersion
        // tier 2,3: random, control + BadMagic coverage
        const tier = i % 4;
        if (tier == 0 and len >= 12) {
            @memcpy(buf[0..5], "%PDF-");
            buf[5] = '1' + rng.uintLessThan(u8, 9);
            buf[6] = '.';
            buf[7] = '0' + rng.uintLessThan(u8, 10);
            // small obj_count so the loop sometimes runs to completion
            std.mem.writeInt(u32, buf[8..12], rng.uintLessThan(u32, 16), .little);
        } else if (tier == 1 and len >= 5) {
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
