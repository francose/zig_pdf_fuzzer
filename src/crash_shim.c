#include "crash_shim.h"
#include <setjmp.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

// single threaded harness, so a global jmp_buf is fine.
// if this ever goes multi thread these become _Thread_local.
static sigjmp_buf g_env;
static volatile sig_atomic_t g_in_protected = 0;

static void crash_handler(int sig) {
    if (g_in_protected) {
        g_in_protected = 0;
        siglongjmp(g_env, 1);
    }
    // outside protection the signal is real, dont try to be clever.
    _exit(128 + sig);
}

void install_crash_handlers(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = crash_handler;
    sa.sa_flags = SA_NODEFER;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
}

int protected_call_pdf(int (*fn)(const unsigned char *, size_t),
                       const unsigned char *data, size_t len,
                       int *result_out) {
    if (sigsetjmp(g_env, 1) != 0) {
        // came back here via siglongjmp from the handler
        return 1;
    }
    g_in_protected = 1;
    int r = fn(data, len);
    g_in_protected = 0;
    if (result_out) *result_out = r;
    return 0;
}

int deliberate_segv(const unsigned char *data, size_t len) {
    (void)data;
    (void)len;
    volatile int *p = (volatile int *)0;
    return *p;
}
