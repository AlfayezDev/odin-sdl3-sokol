// Desktop implementation of binding/api/bridge.h (platform -> odin half:
// the platform_* functions). iOS uses binding/ios/bridge.m, Android uses
// generated JNI glue.
#include <stdio.h>
#include "bridge.h"

void show_toast(const char *msg) {
	printf("[toast] %s\n", msg);
	fflush(stdout);
}
