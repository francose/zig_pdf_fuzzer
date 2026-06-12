const std = @import("std");
const c = @cImport({
    @cInclude("poppler_shim.h");
});

pub const Result = enum {
    parsed,
    rejected,
    context_failure,
};

// poppler side of the differential. pairs with mupdf.openFromMemory.
pub fn openFromMemory(input: []const u8) Result {
    const rc = c.safe_open_pdf_poppler(input.ptr, input.len);
    return switch (rc) {
        1 => .parsed,
        0 => .rejected,
        else => .context_failure,
    };
}
