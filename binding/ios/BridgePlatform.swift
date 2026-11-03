import UIKit

@_cdecl("odinbinder_ios_install")
public func odinbinder_ios_install() {
	OdinBridge.platform = OdinPlatform()
}

private final class OdinPlatform: OdinBridge.PlatformHandler {
	func showToast(_ message: String) {
		DispatchQueue.main.async {
			guard let root = UIApplication.shared.connectedScenes
				.compactMap({ $0 as? UIWindowScene })
				.flatMap({ $0.windows })
				.first(where: { $0.isKeyWindow })?
				.rootViewController else { return }

			let alert = UIAlertController(title: "Odin", message: message, preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: "OK", style: .default))
			(root.presentedViewController ?? root).present(alert, animated: true)
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				alert.dismiss(animated: true)
			}
		}
	}
}
