#include "mupdf_shim.h"
#include <mupdf/fitz.h>

static void quiet_callback(void *user, const char *message) {
    (void)user;
    (void)message;
}

int safe_open_pdf(const unsigned char *data, size_t len) {
    fz_context *ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
    if (!ctx) return -1;

    // silence the "cannot find startxref" chatter so fuzz output stays clean.
    fz_set_warning_callback(ctx, quiet_callback, NULL);
    fz_set_error_callback(ctx, quiet_callback, NULL);

    fz_register_document_handlers(ctx);

    fz_stream *stream = NULL;
    fz_document *doc = NULL;
    int result = 0;

    fz_try(ctx) {
        stream = fz_open_memory(ctx, data, len);
        doc = fz_open_document_with_stream(ctx, "application/pdf", stream);
        result = 1;
    }
    fz_always(ctx) {
        if (doc) fz_drop_document(ctx, doc);
        if (stream) fz_drop_stream(ctx, stream);
    }
    fz_catch(ctx) {
        result = 0;
    }

    fz_drop_context(ctx);
    return result;
}
