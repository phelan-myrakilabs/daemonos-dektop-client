import Foundation
import Observation

/// Drives the ⌃Tab session-switcher HUD. The shell owns the key handling:
/// - first ⌃Tab (not presented)  → `begin(sessionCount:)` — shows the HUD, selects the
///   previous session (alt-tab convention)
/// - subsequent ⌃Tab              → `next()`
/// - ⌃⇧Tab                        → `prev()`
/// - ⌃1…⌃9                        → `select(slot:)`
/// - Ctrl released                → `confirm()` → the shell opens `sessions[index]`
/// - Esc / focus loss             → `cancel()`
@MainActor
@Observable
final class SessionSwitcherPresenter {
    /// The switcher lists at most this many recent sessions; the shell passes the same
    /// cap to `begin` and the view slices `sessions.prefix(maxRows)`.
    static let maxRows = 10

    private(set) var isPresented = false
    private(set) var index = 0
    private var count = 0

    /// Present (or, if already presented, advance). Selects index 1 on first show so a
    /// single ⌃Tab lands on the previous session, like macOS ⌘Tab.
    func begin(sessionCount: Int) {
        let capped = min(sessionCount, Self.maxRows)
        guard capped > 0 else { return }
        if isPresented {
            count = capped
            index = (index + 1) % count
        } else {
            count = capped
            isPresented = true
            index = min(1, count - 1)
        }
    }

    func next() {
        guard isPresented, count > 0 else { return }
        index = (index + 1) % count
    }

    func prev() {
        guard isPresented, count > 0 else { return }
        index = (index - 1 + count) % count
    }

    /// ⌃1…⌃9 direct jump (slot is 1-based). Returns the resolved index (and commits),
    /// or nil when out of range.
    func select(slot: Int) -> Int? {
        let target = slot - 1
        guard target >= 0, target < count else { return nil }
        index = target
        isPresented = false
        return target
    }

    /// Commit the current selection and hide. Returns the selected index, or nil.
    func confirm() -> Int? {
        guard isPresented, count > 0 else { isPresented = false; return nil }
        let selected = index
        isPresented = false
        return selected
    }

    func cancel() {
        isPresented = false
    }
}
