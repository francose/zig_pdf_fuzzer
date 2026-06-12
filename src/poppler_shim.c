#include "poppler_shim.h"
#include <poppler.h>
#include <glib.h>

int safe_open_pdf_poppler(const unsigned char *data, size_t len) {
    GBytes *bytes = g_bytes_new_static(data, len);
    if (!bytes) return -1;

    GError *err = NULL;
    PopplerDocument *doc = poppler_document_new_from_bytes(bytes, NULL, &err);

    g_bytes_unref(bytes);
    if (err) g_error_free(err);

    if (!doc) return 0;
    g_object_unref(doc);
    return 1;
}
