import AppKit
import SwiftUI

/// Nudges the macOS traffic lights rightward to ~24pt so they sit under the
/// titlebar band's nav cluster (TitlebarView insets that cluster 98pt = 24 + 74).
/// macOS re-lays the buttons out on resize, so we re-apply on the window's resize
/// notification. Only the x-origin is adjusted; the system's vertical centering in
/// the title bar is preserved.
struct TrafficLightPositioner: NSViewRepresentable {
    /// Leftmost button x-origin (reference traffic-light x = 24).
    static let insetX: CGFloat = 24
    static let spacing: CGFloat = 20

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.bind(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.bind(to: nsView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private weak var window: NSWindow?
        private var resizeObserver: NSObjectProtocol?

        func bind(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }
                if self.window !== window {
                    self.window = window
                    if let resizeObserver = self.resizeObserver {
                        NotificationCenter.default.removeObserver(resizeObserver)
                    }
                    self.resizeObserver = NotificationCenter.default.addObserver(
                        forName: NSWindow.didResizeNotification, object: window, queue: .main
                    ) { [weak self] _ in self?.reposition() }
                }
                self.reposition()
            }
        }

        private func reposition() {
            guard let window else { return }
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                .compactMap { window.standardWindowButton($0) }
            guard buttons.count == 3 else { return }
            for (index, button) in buttons.enumerated() {
                let origin = NSPoint(
                    x: TrafficLightPositioner.insetX + CGFloat(index) * TrafficLightPositioner.spacing,
                    y: button.frame.origin.y
                )
                button.setFrameOrigin(origin)
            }
        }
    }
}
