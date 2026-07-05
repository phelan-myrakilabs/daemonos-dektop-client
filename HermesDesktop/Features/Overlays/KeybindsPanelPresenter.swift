import Foundation
import Observation

/// Drives the ⌘/ keyboard-shortcuts panel.
@MainActor
@Observable
final class KeybindsPanelPresenter {
    private(set) var isPresented = false

    func toggle() { isPresented.toggle() }
    func open() { isPresented = true }
    func close() { isPresented = false }
}
