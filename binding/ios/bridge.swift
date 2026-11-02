// iOS implementation of binding/api/bridge.h (platform -> odin half:
// the platform_* functions). The C header is imported through
// binding/ios/Bridging.h; @_cdecl exposes these symbols with C ABI so
// Odin's foreign calls land here. Android uses generated JNI glue,
// desktop uses binding/desktop/bridge.c.
import UIKit

@_cdecl("platform_show_toast")
public func platformShowToast(msg: UnsafePointer<CChar>) {
	let message = String(cString: msg)
	DispatchQueue.main.async {
		let alert = UIAlertController(title: "Odin", message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "OK", style: .default))
		(UIApplication.shared.keyWindow?.rootViewController ?? UIApplication.shared.connectedScenes
			.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
			.first)?
			.present(alert, animated: true)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
			alert.dismiss(animated: true)
		}
	}
}
