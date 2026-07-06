import AppKit
import SwiftUI

/// Artifacts surface: images / files / links extracted from recent sessions'
/// messages, filterable by kind. Opening a link/image uses the system browser;
/// file paths are agent-side, so they show the path with copy (remote client has
/// no media endpoint for arbitrary paths — Phase 3).
struct ArtifactsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatCoordinator.self) private var chat
    @Environment(\.hermesTheme) private var theme

    @State private var store: ArtifactsStore?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.appBackground)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: HermesTheme.titlebarHeight)
        }
        .onAppear { if store == nil { store = ArtifactsStore(rest: model.rest) } }
        .task(id: availabilityKey) {
            guard let store else { return }
            store.isAvailable = model.connectionStore.settings.mode == .gateway && model.boot.isReady
            await store.refresh()
        }
    }

    private var availabilityKey: String {
        "\(model.connectionStore.settings.mode.rawValue)-\(model.boot.isReady)"
    }

    @ViewBuilder
    private func content(_ store: ArtifactsStore) -> some View {
        if !store.isAvailable {
            unavailable
        } else {
            VStack(spacing: 0) {
                header(store)
                Divider().overlay(theme.hairline)
                body(store)
            }
        }
    }

    // MARK: - Header (search + filter tabs)

    @ViewBuilder
    private func header(_ store: ArtifactsStore) -> some View {
        @Bindable var store = store
        let c = store.counts
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                TextField("Search artifacts…", text: $store.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Refresh artifacts")
            }
            HStack(spacing: 6) {
                filterTab("All", count: c.all, kind: nil, store: store)
                filterTab("Images", count: c.image, kind: .image, store: store)
                filterTab("Files", count: c.file, kind: .file, store: store)
                filterTab("Links", count: c.link, kind: .link, store: store)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func filterTab(_ label: String, count: Int, kind: ArtifactRecord.Kind?, store: ArtifactsStore) -> some View {
        let active = store.filter == kind
        return Button {
            store.filter = active ? nil : kind
        } label: {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 11, weight: .medium))
                Text("\(count)").font(.system(size: 11)).foregroundStyle(theme.textTertiary)
            }
            .foregroundStyle(active ? theme.accentForeground : theme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(active ? theme.accent : theme.textPrimary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Body

    @ViewBuilder
    private func body(_ store: ArtifactsStore) -> some View {
        switch store.phase {
        case .idle, .loading:
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Indexing recent session artifacts")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 10) {
                Text("Artifacts failed to load")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(message).font(.system(size: 12)).foregroundStyle(theme.textTertiary)
                Button("Retry") { Task { await store.refresh() } }.buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if store.visible.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.textDisabled)
                    Text("No artifacts found")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Generated images and file outputs will appear here as sessions produce them.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(store.visible) { artifact in
                            ArtifactRow(artifact: artifact) { open(artifact) } openSession: {
                                openSession(artifact)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 22))
                .foregroundStyle(theme.textDisabled)
            Text("Artifacts need the Hermes gateway")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Switch to the Hermes gateway connection mode in Settings to index your sessions' generated images, files, and links.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func open(_ artifact: ArtifactRecord) {
        switch artifact.kind {
        case .link, .image:
            if artifact.value.hasPrefix("http"), let url = URL(string: artifact.value) {
                NSWorkspace.shared.open(url)
            } else if artifact.value.hasPrefix("data:") {
                // data: images can't be handed to the browser cleanly; copy instead.
                copy(artifact.value)
            } else {
                copy(artifact.value)
            }
        case .file:
            // Agent-side path: no remote media endpoint yet — copy the path.
            copy(artifact.value)
        }
    }

    private func openSession(_ artifact: ArtifactRecord) {
        let session = SessionInfoStub.make(id: artifact.sessionID, title: artifact.sessionTitle)
        chat.openSession(session)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Row

private struct ArtifactRow: View {
    let artifact: ArtifactRecord
    let open: () -> Void
    let openSession: () -> Void

    @Environment(\.hermesTheme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(artifact.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(theme.textPrimary)
                Button(action: openSession) {
                    Text(artifact.sessionTitle)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Open session")
            }
            Spacer(minLength: 8)
            if hovering {
                Button(action: open) {
                    Image(systemName: artifact.kind == .file ? "doc.on.doc" : "arrow.up.right.square")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help(artifact.kind == .file ? "Copy path" : "Open")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: HermesRadius.sm, style: .continuous)
                .fill(hovering ? theme.textPrimary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
    }

    private var icon: String {
        switch artifact.kind {
        case .image: return "photo"
        case .file: return "doc.text"
        case .link: return "link"
        }
    }
}

/// Minimal SessionInfo builder so an artifact row can reopen its source session by
/// id (only id/title are needed to navigate; the view model hydrates the rest).
private enum SessionInfoStub {
    static func make(id: String, title: String) -> SessionInfo {
        let json: JSONValue = .object([
            "id": .string(id),
            "title": .string(title),
        ])
        // Decoding can't fail: id is present and all other fields are optional.
        return (try? json.decoded(as: SessionInfo.self)) ?? placeholder(id: id)
    }

    private static func placeholder(id: String) -> SessionInfo {
        let json: JSONValue = .object(["id": .string(id)])
        return try! json.decoded(as: SessionInfo.self)
    }
}
