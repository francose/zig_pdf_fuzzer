const std = @import("std");
const c = @cImport({
    @cInclude("mupdf_shim.h");
});

pub const Result = enum {
    parsed,
    rejected,
    context_failure,
};

// returns whether mupdf accepted the bytes. shim handles the fz_try stuff.
pub fn openFromMemory(input: []const u8) Result {
    const rc = c.safe_open_pdf(input.ptr, input.len);
    return switch (rc) {
        1 => .parsed,
        0 => .rejected,
        else => .context_failure,
    };
}
