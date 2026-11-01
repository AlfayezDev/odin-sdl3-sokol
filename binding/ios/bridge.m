// iOS implementation of binding/api/bridge.h (platform -> odin half:
// the platform_* functions). Android uses generated JNI glue, desktop
// uses binding/desktop/bridge.c.
#import <UIKit/UIKit.h>
#include "bridge.h"

void platform_show_toast(const char *msg) {
	NSString *string = [NSString stringWithUTF8String:msg];
	NSLog(@"[toast] %@", string);
	// fire on the main thread; dismiss after a beat so it reads like a toast
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertController *alert =
			[UIAlertController alertControllerWithTitle:@"Odin" message:string
							 preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
		[[UIApplication sharedApplication].keyWindow.rootViewController
			presentViewController:alert animated:YES completion:nil];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ [alert dismissViewControllerAnimated:YES completion:nil]; });
	});
}
