const std = @import("std");
const c = @cImport({
    @cInclude("mupdf_shim.h");
});

pub const Result = enum {
    parsed,
    rejected,
    context_failure,
};

// Feed bytes into MuPDF and see whether it accepts them as a PDF.
// Calls into the C shim which wraps MuPDF's setjmp/longjmp error path,
// so this is safe to call from Zig without worrying about non-local
// control flow leaking up the stack.
pub fn openFromMemory(input: []const u8) Result {
    const rc = c.safe_open_pdf(input.ptr, input.len);
    return switch (rc) {
        1 => .parsed,
        0 => .rejected,
        else => .context_failure,
    };
}
