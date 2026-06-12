const std = @import("std");
const c = @cImport({
    @cInclude("poppler_shim.h");
});

pub const Result = enum {
    parsed,
    rejected,
    context_failure,
};

// Feed bytes into poppler-glib and see whether it accepts them as a PDF.
// Used together with mupdf.openFromMemory for differential fuzzing: if
// the two parsers disagree on whether a buffer is a valid PDF, that's
// either a bug in one of them or a place the PDF spec leaves room for
// interpretation. Both are worth saving.
pub fn openFromMemory(input: []const u8) Result {
    const rc = c.safe_open_pdf_poppler(input.ptr, input.len);
    return switch (rc) {
        1 => .parsed,
        0 => .rejected,
        else => .context_failure,
    };
}
