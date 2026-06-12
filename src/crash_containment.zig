const std = @import("std");
const c = @cImport({
    @cInclude("crash_shim.h");
    @cInclude("mupdf_shim.h");
    @cInclude("poppler_shim.h");
});

pub const Outcome = enum {
    parsed,
    rejected,
    context_failure,
    crashed,
};

// call once at startup. safe to call again.
pub fn installHandlers() void {
    c.install_crash_handlers();
}

// all three shims share the same int(ptr, len) signature so one wrapper does.
fn callProtected(
    func: *const fn ([*c]const u8, usize) callconv(.c) c_int,
    input: []const u8,
) Outcome {
    var rc: c_int = 0;
    const crashed = c.protected_call_pdf(func, input.ptr, input.len, &rc);
    if (crashed != 0) return .crashed;
    return switch (rc) {
        1 => .parsed,
        0 => .rejected,
        else => .context_failure,
    };
}

pub fn mupdfOpen(input: []const u8) Outcome {
    return callProtected(c.safe_open_pdf, input);
}

pub fn popplerOpen(input: []const u8) Outcome {
    return callProtected(c.safe_open_pdf_poppler, input);
}

// test only. null deref to prove the recovery works.
pub fn triggerSegv(input: []const u8) Outcome {
    return callProtected(c.deliberate_segv, input);
}
