import Foundation
import Observation

/// Which overlay is open. One at a time (reference: dialogs are mutually
/// exclusive; opening one closes the last).
enum OverlayRoute: Equatable {
    case commandPalette
    case sessionPicker
    case modelPicker
}

/// Owns the single open overlay route. The Shell wires ⌘K/⌘P to
/// `toggle(.commandPalette)`; Esc and backdrop clicks call `close()`.
@MainActor
@Observable
final class OverlayCoordinator {
    private(set) var route: OverlayRoute?

    func open(_ route: OverlayRoute) {
        self.route = route
    }

    func toggle(_ route: OverlayRoute) {
        self.route = self.route == route ? nil : route
    }

    func close() {
        route = nil
    }
}

/// Notification stack store (reference `notify()` / `notifyError()`).
/// Non-sticky toasts auto-dismiss after ~4 s; sticky ones stay until closed.
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id: UUID
        var title: String
        var message: String?
        var isError: Bool
        var sticky: Bool
    }

    static let autoDismissDelay: TimeInterval = 4

    private(set) var toasts: [Toast] = []
    @ObservationIgnored private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    func post(title: String, message: String? = nil, isError: Bool = false, sticky: Bool = false) {
        let toast = Toast(id: UUID(), title: title, message: message, isError: isError, sticky: sticky)
        toasts.append(toast)
        guard !sticky else { return }
        dismissTasks[toast.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.autoDismissDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss(id: toast.id)
        }
    }

    func dismiss(id: UUID) {
        dismissTasks.removeValue(forKey: id)?.cancel()
        toasts.removeAll { $0.id == id }
    }

    func clearAll() {
        for task in dismissTasks.values { task.cancel() }
        dismissTasks = [:]
        toasts = []
    }
}
