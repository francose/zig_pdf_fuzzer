#ifndef CRASH_SHIM_H
#define CRASH_SHIM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Install SIGSEGV / SIGBUS / SIGABRT handlers that siglongjmp back into
// a protected_call_pdf invocation. Call once at harness startup.
void install_crash_handlers(void);

// Call `fn(data, len)` under crash protection. If `fn` segfaults / busfaults
// / aborts, the harness unwinds back here and `*result_out` is left
// unchanged. Otherwise `*result_out` receives whatever `fn` returned.
//
// Returns:
//   0 on normal completion
//   1 on caught signal
int protected_call_pdf(int (*fn)(const unsigned char *, size_t),
                       const unsigned char *data, size_t len,
                       int *result_out);

// Test helper: deliberately dereference a NULL pointer. Used to verify
// the crash containment harness actually catches a SIGSEGV.
int deliberate_segv(const unsigned char *data, size_t len);

#ifdef __cplusplus
}
#endif

#endif
