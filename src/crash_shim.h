#ifndef CRASH_SHIM_H
#define CRASH_SHIM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// call once before any protected_call_pdf
void install_crash_handlers(void);

// runs fn(data, len) under signal protection.
// returns 0 normal, 1 if a crash was caught and unwound.
int protected_call_pdf(int (*fn)(const unsigned char *, size_t),
                       const unsigned char *data, size_t len,
                       int *result_out);

// null deref. used by the test to confirm we actually recover.
int deliberate_segv(const unsigned char *data, size_t len);

#ifdef __cplusplus
}
#endif

#endif
