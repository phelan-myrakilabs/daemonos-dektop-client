import Foundation
import Observation

/// First-run state, backed by a UserDefaults flag. `shouldShow` is true until the
/// user completes onboarding once.
@MainActor
@Observable
final class OnboardingState {
    private static let completedKey = "onboarding.completed"

    private let defaults: UserDefaults
    private(set) var shouldShow: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.shouldShow = !defaults.bool(forKey: Self.completedKey)
    }

    func complete() {
        defaults.set(true, forKey: Self.completedKey)
        shouldShow = false
    }

    /// Test/dev hook — re-arm the first-run card.
    func reset() {
        defaults.set(false, forKey: Self.completedKey)
        shouldShow = true
    }
}
