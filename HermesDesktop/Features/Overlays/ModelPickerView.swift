import SwiftUI

/// Model picker dialog (reference `components/model-picker.tsx`). Phase 2 is
/// display-only: it lists what the backend offers; applying a selection to a
/// session lands in a later phase (no model-switch RPC is invented here).
struct ModelPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.hermesTheme) private var theme

    private enum Phase: Equatable {
        case loading
        case loaded(ModelOptionsResponse)
        case failed(String)
    }

    @State private var phase: Phase = .loading

    private var isV1Mode: Bool { model.connectionStore.settings.mode == .v1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.hairline)
            content
                .frame(maxHeight: 380)
            Divider().overlay(theme.hairline)
            Text("Model switching lands in a later phase — this list is read-only for now.")
                .font(.system(size: 10))
                .foregroundStyle(theme.textDisabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlayPanelChrome(width: 560)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            Text("Models")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            if case .loading = phase {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            Text("Loading model options…")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity)
        case .failed(let message):
            VStack(spacing: 6) {
                Text("Could not load model options")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.statusError)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        case .loaded(let options):
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(options.providers ?? [], id: \.slug) { provider in
                        providerSection(provider, currentModel: options.model)
                    }
                }
                .padding(6)
            }
        }
    }

    @ViewBuilder
    private func providerSection(_ provider: ModelOptionProvider, currentModel: String?) -> some View {
        HStack(spacing: 6) {
            Text(provider.name.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(theme.primary)
            if provider.authenticated == false {
                Text("not configured")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textDisabled)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(theme.codeBackground)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 3)

        ForEach(provider.models ?? [], id: \.self) { modelID in
            modelRow(modelID,
                     provider: provider,
                     isCurrent: provider.isCurrent == true && modelID == currentModel)
        }
    }

    private func modelRow(_ modelID: String, provider: ModelOptionProvider, isCurrent: Bool) -> some View {
        let pricing = provider.pricing?[modelID]
        let unavailable = provider.unavailableModels?.contains(modelID) == true
        return HStack(spacing: 8) {
            Image(systemName: isCurrent ? "checkmark" : "circle")
                .font(.system(size: isCurrent ? 10 : 5))
                .foregroundStyle(isCurrent ? theme.primary : theme.textDisabled.opacity(0.4))
                .frame(width: 14)
            Text(modelID)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(unavailable ? theme.textDisabled : theme.textPrimary)
            if provider.capabilities?[modelID]?.fast == true {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(theme.statusWarning)
                    .help("Supports fast mode")
            }
            Spacer(minLength: 8)
            if let pricing {
                Text(pricing.free ? "free" : "\(pricing.input) in · \(pricing.output) out")
                    .font(HermesTheme.monoFont(size: 9))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .opacity(unavailable ? 0.6 : 1)
        .help(unavailable ? "Not available on the free tier" : "")
    }

    // MARK: - Data

    private func load() async {
        if isV1Mode {
            // v1 exposes a single model; mirror /v1/models without a network hop
            // (the boot health check already validated reachability).
            let provider = ModelOptionProvider(
                isCurrent: true,
                models: [AppModel.defaultV1Model],
                name: "Hermes",
                slug: "hermes",
                totalModels: 1,
                warning: nil,
                authenticated: true,
                authType: nil,
                keyEnv: nil,
                isUserDefined: nil,
                pricing: nil,
                freeTier: nil,
                unavailableModels: nil,
                capabilities: nil
            )
            phase = .loaded(ModelOptionsResponse(model: AppModel.defaultV1Model,
                                                 provider: "hermes",
                                                 providers: [provider]))
            return
        }
        do {
            // Use the cached catalog on open (reference keeps the 1h cache for normal
            // opens); refresh=1 is reserved for an explicit user-triggered refresh so
            // opening the picker doesn't re-fetch every provider's live catalog.
            let response = try await model.rest.request("/api/model/options",
                                                        timeout: HermesRESTClient.startupTimeout,
                                                        as: ModelOptionsResponse.self)
            phase = .loaded(response)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
