const std = @import("std");

pub const ParseError = error{
    BadMagic,
    BadVersion,
};

// Stub parser. Stand-in for the real poppler/MuPDF hook we'll wire in next.
// Has intentional out-of-bounds bugs so the fuzzer has something to find
// on day one.
pub fn parsePdfHeader(input: []const u8) ParseError!void {
    if (!std.mem.eql(u8, input[0..5], "%PDF-")) {
        return error.BadMagic;
    }

    const major = input[5];
    const minor = input[7];
    if (major < '1' or major > '9') return error.BadVersion;
    if (minor < '0' or minor > '9') return error.BadVersion;

    const obj_count = std.mem.readInt(u32, input[8..12], .little);
    var cursor: usize = 12;
    var i: u32 = 0;
    while (i < obj_count) : (i += 1) {
        const len = std.mem.readInt(u16, input[cursor..][0..2], .little);
        cursor += 2;
        _ = input[cursor .. cursor + len];
        cursor += len;
    }
}
