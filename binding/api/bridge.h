/*
 * bridge.h — single source of truth for Odin <-> platform bindings.
 *
 *   odin_*     : implemented in Odin via @(export); consumed by platforms
 *                (Kotlin through JNI glue, ObjC/Swift directly).
 *   platform_* : implemented per platform (ObjC on iOS, JNI glue on Android,
 *                desktop stub); consumed by Odin through vendors/bridge.
 *
 * Conventions:
 *   - Returned const char* is static/borrowed — never freed by the caller.
 *   - Passed-in const char* is copied by the receiver if it is retained.
 *   - Supported types (phase 1): void, bool, int32_t, float, const char*.
 */
#ifndef BRIDGE_H
#define BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* platform -> odin */

/* Returns a static greeting owned by the Odin side. */
const char *odin_hello(void);

/* Adds two numbers; proves scalar marshaling in both generators. */
int32_t odin_add(int32_t a, int32_t b);

/* odin -> platform */

/* Shows a short transient message on the platform UI (Toast / alert / log). */
/* @jni dev.alfayez.odinsokol.OdinBridge */
void platform_show_toast(const char *msg);

#ifdef __cplusplus
}
#endif

#endif /* BRIDGE_H */
