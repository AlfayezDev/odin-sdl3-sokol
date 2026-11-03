// Desktop implementation of the import half of binding/api/bridge.h.
// iOS uses binding/ios/BridgePlatform.swift, Android uses generated JNI glue.
#include <stdio.h>
#include "bridge.h"

void show_toast(const char *msg) {
	printf("[toast] %s\n", msg);
	fflush(stdout);
}
