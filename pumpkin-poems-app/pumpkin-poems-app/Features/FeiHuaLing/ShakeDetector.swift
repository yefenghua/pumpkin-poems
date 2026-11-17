import SwiftUI
import UIKit

/// Receives iPhone's native shake gesture only while the game is accepting letters.
struct ShakeDetector: UIViewControllerRepresentable {
    var enabled: Bool
    var onShake: () -> Void

    func makeUIViewController(context: Context) -> ShakeController {
        let controller = ShakeController()
        controller.onShake = onShake
        controller.setEnabled(enabled)
        return controller
    }

    func updateUIViewController(_ controller: ShakeController, context: Context) {
        controller.onShake = onShake
        controller.setEnabled(enabled)
    }

    static func dismantleUIViewController(_ controller: ShakeController, coordinator: ()) {
        controller.setEnabled(false)
        controller.onShake = nil
    }

    final class ShakeController: UIViewController {
        var onShake: (() -> Void)?
        private var enabled = false
        private var visible = false

        private var shouldListen: Bool {
            enabled && visible && viewIfLoaded?.window?.windowScene?.activationState == .foregroundActive
        }

        override var canBecomeFirstResponder: Bool { shouldListen }

        override func loadView() {
            // Stay eligible to receive responder events while letting every touch pass
            // through this invisible background to the SwiftUI game.
            let background = TouchThroughView()
            background.backgroundColor = .clear
            background.isUserInteractionEnabled = true
            background.isAccessibilityElement = false
            view = background
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            visible = true
            updateResponder()
        }

        override func viewWillDisappear(_ animated: Bool) {
            visible = false
            updateResponder()
            super.viewWillDisappear(animated)
        }

        func setEnabled(_ value: Bool) {
            guard enabled != value else { return }
            enabled = value
            updateResponder()
        }

        private func updateResponder() {
            guard shouldListen else {
                if isFirstResponder { resignFirstResponder() }
                return
            }
            // Wait until SwiftUI's containment/window update is complete. Recheck all
            // gates in case a sheet, navigation change, or backgrounding intervenes.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.shouldListen, !self.isFirstResponder else { return }
                self.becomeFirstResponder()
            }
        }

        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            if shouldListen, isFirstResponder, motion == .motionShake { onShake?() }
            else { super.motionEnded(motion, with: event) }
        }
    }

    private final class TouchThroughView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }
}
