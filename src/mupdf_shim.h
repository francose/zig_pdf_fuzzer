#ifndef MUPDF_SHIM_H
#define MUPDF_SHIM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Try to open `data` of length `len` as a PDF using MuPDF. MuPDF's
// own error path uses setjmp/longjmp via the fz_try / fz_catch macros,
// which @cImport can't see through, so this shim wraps the open path
// behind a plain C function the Zig side can call.
//
// Return values:
//    1  parsed and opened the document
//    0  MuPDF rejected the input (most fuzz inputs land here)
//   -1  internal context creation failed (very rare)
int safe_open_pdf(const unsigned char *data, size_t len);

#ifdef __cplusplus
}
#endif

#endif
