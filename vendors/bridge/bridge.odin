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
package bridge

foreign import lib "../../build/desktop/libbridge.a"
_ :: lib

@(default_calling_convention="c")
foreign lib {
	/* Shows a short transient message on the platform UI (Toast / alert / log). */
	/* @jni dev.alfayez.odinsokol.OdinBridge */
	platform_show_toast :: proc(msg: cstring) ---
}

