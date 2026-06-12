#ifndef POPPLER_SHIM_H
#define POPPLER_SHIM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// poppler version of the mupdf shim. same return shape:
// 1 parsed, 0 rejected, -1 alloc fail.
int safe_open_pdf_poppler(const unsigned char *data, size_t len);

#ifdef __cplusplus
}
#endif

#endif
