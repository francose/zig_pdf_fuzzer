#ifndef MUPDF_SHIM_H
#define MUPDF_SHIM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// wraps mupdf's fz_try so zig dosnt have to see the setjmp macro.
// returns 1 parsed, 0 rejected, -1 ctx failure.
int safe_open_pdf(const unsigned char *data, size_t len);

#ifdef __cplusplus
}
#endif

#endif
