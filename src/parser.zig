const std = @import("std");

pub const ParseError = error{
    BadMagic,
    BadVersion,
    Truncated,
};

// stub parser. stand in for the real mupdf/poppler hook.
pub fn parsePdfHeader(input: []const u8) ParseError!void {
    if (input.len < 5 or !std.mem.eql(u8, input[0..5], "%PDF-")) {
        return error.BadMagic;
    }

    if (input.len < 12) return error.Truncated;

    const major = input[5];
    const minor = input[7];
    if (major < '1' or major > '9') return error.BadVersion;
    if (minor < '0' or minor > '9') return error.BadVersion;

    const obj_count = std.mem.readInt(u32, input[8..12], .little);
    var cursor: usize = 12;
    var i: u32 = 0;
    while (i < obj_count) : (i += 1) {
        if (input.len < cursor + 2) return error.Truncated;
        const len = std.mem.readInt(u16, input[cursor..][0..2], .little);
        cursor += 2;
        if (input.len < cursor + len) return error.Truncated;
        _ = input[cursor .. cursor + len];
        cursor += len;
    }
}

// the answer for this parser issue is Zig wont check slice bounds for you at the complie time,
// if you write input[0..5] and you must first know input.len >= 5 or you panic at runtime.
