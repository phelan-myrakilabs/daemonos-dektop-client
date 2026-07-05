import SwiftUI

/// Root of the macOS Settings scene — `Settings { SettingsRootView() }`.
/// Expects `AppModel` and `ThemeStore` in the environment
/// (`.environment(model)` / `.environment(themeStore)`).
struct SettingsRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var themeStore

    var body: some View {
        TabView {
            GatewaySettingsView()
                .tabItem { Label("Gateway", systemImage: "network") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .environment(\.hermesTheme, themeStore.theme)
        .frame(width: 560)
    }
}

/// Appearance tab: skin picker over the skin registry + light/dark mode toggle.
private struct AppearanceSettingsView: View {
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.hermesTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader("Color mode")
                .padding(.bottom, 2)
            HStack {
                Text("Dark mode")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Toggle("Dark mode", isOn: darkModeBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .frame(minHeight: HermesTheme.sessionRowHeight)

            SettingsHairline()
                .padding(.vertical, 12)

            SettingsSectionHeader("Skin")
                .padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(HermesSkinLibrary.skinOrder, id: \.self) { name in
                    skinRow(name)
                    if name != HermesSkinLibrary.skinOrder.last {
                        SettingsHairline()
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.appBackground)
    }

    private var darkModeBinding: Binding<Bool> {
        Binding(
            get: { themeStore.isDark },
            set: { newValue in
                if newValue != themeStore.isDark {
                    themeStore.toggleMode()
                }
            }
        )
    }

    private func skinRow(_ name: String) -> some View {
        Button {
            themeStore.setSkin(name)
        } label: {
            HStack(spacing: 8) {
                swatch(for: name)
                Text(name.capitalized)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if themeStore.skinName == name {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .frame(height: HermesTheme.sessionRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func swatch(for name: String) -> some View {
        let resolved = HermesSkinLibrary.resolve(skinName: name, isDark: themeStore.isDark)
        return RoundedRectangle(cornerRadius: HermesTheme.radius(6))
            .fill(resolved.appBackground)
            .overlay(
                Circle()
                    .fill(resolved.accent)
                    .frame(width: 6, height: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HermesTheme.radius(6))
                    .stroke(theme.strokePrimary, lineWidth: 1)
            )
            .frame(width: 16, height: 16)
    }
}

// MARK: - Shared flat-row primitives (ui-shell visual language)

struct SettingsSectionHeader: View {
    @Environment(\.hermesTheme) private var theme
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(theme.textTertiary)
    }
}

struct SettingsHairline: View {
    @Environment(\.hermesTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.hairline)
            .frame(height: 1)
    }
}
