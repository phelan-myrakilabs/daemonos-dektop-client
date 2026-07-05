import SwiftUI

@main
struct HermesDesktopApp: App {
    @State private var model = AppModel()
    @State private var themeStore = ThemeStore()
    @State private var overlays = OverlayCoordinator()
    @State private var toasts = ToastCenter()
    @State private var onboarding = OnboardingState()
    @State private var sessionSwitcher = SessionSwitcherPresenter()
    @State private var keybinds = KeybindsPanelPresenter()
    @State private var chatCoordinator: ChatCoordinator?

    var body: some Scene {
        WindowGroup {
            Group {
                if let chatCoordinator {
                    ShellRootView()
                        .environment(chatCoordinator)
                } else {
                    Color.clear
                        .onAppear { chatCoordinator = ChatCoordinator(model: model) }
                }
            }
            .environment(model)
            .environment(themeStore)
            .environment(overlays)
            .environment(toasts)
            .environment(onboarding)
            .environment(sessionSwitcher)
            .environment(keybinds)
            .environment(\.hermesTheme, themeStore.theme)
            .background(TrafficLightPositioner())
            .task { model.boot.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands { ShellCommands() }

        Settings {
            SettingsRootView()
                .environment(model)
                .environment(themeStore)
        }
    }
}
