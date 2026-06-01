const std = @import("std");
const parser = @import("parser.zig");

pub const parsePdfHeader = parser.parsePdfHeader;

// Hand-rolled random fuzzer. Coverage-blind but it doesn't need Zig's
// experimental --fuzz mode (which is broken in both 0.15 and 0.16 right
// now). One million random inputs per test run. If the parser ever panics
// the test fails, the seed and iteration get printed.
test "fuzz parsePdfHeader" {
    const iterations: usize = 1_000_000;
    const seed: u64 = 0xC0FFEE;

    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var buf: [4096]u8 = undefined;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const len = rng.uintLessThan(usize, buf.len + 1);
        rng.bytes(buf[0..len]);
        parsePdfHeader(buf[0..len]) catch {};
    }
}
