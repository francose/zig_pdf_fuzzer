#ifndef POPPLER_SHIM_H
#define POPPLER_SHIM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Try to open `data` of length `len` as a PDF using poppler-glib. Poppler
// uses GError-style error reporting (no setjmp), so the shim is thinner
// than the MuPDF one: it exists mainly to keep glib/poppler headers out
// of the Zig @cImport graph.
//
// Return values:
//    1  parsed and opened the document
//    0  poppler rejected the input
//   -1  GBytes allocation failed (very rare)
int safe_open_pdf_poppler(const unsigned char *data, size_t len);

#ifdef __cplusplus
}
#endif

#endif
