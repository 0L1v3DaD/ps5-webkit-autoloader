/*
 * HTTP Server - serves the cached frontend files from the generated file
 * registry and handles the /cache_complete shutdown signal.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
#include <microhttpd.h>

#include "wkali.h"
#include "http_server.h"
#include "file_registry.h"

/* CORS is intentionally `*`: the installer page is also served from the PC
 * host (manuals.playstation.net over HTTPS), which cross-origin XHRs this
 * on-console server (http://127.0.0.1:18181) for /version and
 * /cache_complete. The server binds 127.0.0.1 only and lives for seconds.
 * Do not restrict unless that flow changes. */
#define CORS_ORIGIN "*"

/* Shared flag — set to 0 by /cache_complete, read by the main loop.
 * atomic so the store in a connection thread is visible to the main loop. */
atomic_int http_keep_running = 1;

static void add_cors_headers(struct MHD_Response *resp) {
    MHD_add_response_header(resp, "Access-Control-Allow-Origin", CORS_ORIGIN);
}

static const FileEntry *registry_lookup(const char *url) {
    if (strcmp(url, ROUTE_INDEX) == 0)
        return file_registry_find(ROUTE_INDEX_HTML);
    return file_registry_find(url);
}

enum MHD_Result http_on_request(void *cls, struct MHD_Connection *conn,
                                const char *url, const char *method,
                                const char *version, const char *upload_data,
                                size_t *upload_data_size, void **con_cls) {

    (void)cls;
    (void)version;
    (void)upload_data;
    (void)upload_data_size;

    /* Handle CORS Preflight (OPTIONS) */
    if (strcmp(method, "OPTIONS") == 0) {
        struct MHD_Response *resp =
            MHD_create_response_from_buffer(0, NULL, MHD_RESPMEM_PERSISTENT);
        add_cors_headers(resp);
        MHD_add_response_header(resp, "Access-Control-Allow-Methods",
                                "GET, OPTIONS");
        MHD_add_response_header(resp, "Access-Control-Allow-Headers",
                                "Content-Type");
        enum MHD_Result ret = MHD_queue_response(conn, MHD_HTTP_OK, resp);
        MHD_destroy_response(resp);
        return ret;
    }

    /* ── Initial call for a new request ────────────────────── */
    if (*con_cls == NULL) {
        *con_cls = (void *)1;
        return MHD_YES;
    }

    struct MHD_Response *resp = NULL;
    int http_status = MHD_HTTP_OK;

    if (strcmp(url, ROUTE_CACHE_COMPLETE) == 0) {
        wkali_log("[WKALI] Cache complete signal received. Shutting down...\n");
        resp = MHD_create_response_from_buffer(strlen("OK"), (void *)"OK",
                                               MHD_RESPMEM_PERSISTENT);
        MHD_add_response_header(resp, "Content-Type", "text/plain");
        atomic_store(&http_keep_running, 0);
    } else if (strcmp(url, ROUTE_VERSION) == 0) {
        resp = MHD_create_response_from_buffer(strlen(WKAL_FULL_VERSION),
                                               (void *)WKAL_FULL_VERSION,
                                               MHD_RESPMEM_PERSISTENT);
        MHD_add_response_header(resp, "Content-Type", "text/plain");
    } else {
        const FileEntry *entry = registry_lookup(url);
        if (entry) {
            resp = MHD_create_response_from_buffer(entry->size,
                                                   (void *)entry->data,
                                                   MHD_RESPMEM_PERSISTENT);
            MHD_add_response_header(resp, "Content-Type", entry->content_type);
            if (strcmp(url, ROUTE_CACHE_MANIFEST) == 0 ||
                strstr(entry->content_type, "text/html") != NULL) {
                MHD_add_response_header(resp, "Cache-Control",
                                        "no-cache, must-revalidate");
            }
        } else {
            const char *not_found = "404 Not Found\n";
            resp = MHD_create_response_from_buffer(strlen(not_found),
                                                   (void *)not_found,
                                                   MHD_RESPMEM_PERSISTENT);
            MHD_add_response_header(resp, "Content-Type", "text/plain");
            http_status = MHD_HTTP_NOT_FOUND;
        }
    }

    if (!resp)
        return MHD_NO;

    add_cors_headers(resp);
    enum MHD_Result ret = MHD_queue_response(conn, http_status, resp);
    MHD_destroy_response(resp);

    return ret;
}
