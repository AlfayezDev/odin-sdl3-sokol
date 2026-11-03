import UIKit

@_cdecl("odinbinder_ios_install")
public func odinbinder_ios_install() {
	OdinBridge.platform = OdinPlatform()
}

private final class OdinPlatform: OdinBridge.PlatformHandler {
	func showToast(_ message: String) {
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
}
