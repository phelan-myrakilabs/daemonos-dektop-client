# Hermes Desktop (Swift)

A native macOS client for the Hermes Agent gateway, written from scratch in Swift +
SwiftUI. It recreates the original Electron/React desktop app — same layout, screens,
visual design, and chat/streaming behavior — with one deliberate architectural change:
**it is a pure remote client**. It does not bundle, install, spawn, or manage a Python
backend, and it has no local or SSH mode. It talks over the network to an
already-running Hermes gateway exposed through Cloudflare tunnels.

## Two connection modes

The client speaks two backend protocols, selected in **Settings → Gateway**:

| Mode | Default endpoint | Auth | What it gives you |
|---|---|---|---|
| **OpenAI-compatible `/v1`** (default) | `https://api-hermes.myrakilabs.com` | `Authorization: Bearer <API key>` | Streaming chat with the Hermes agent (`POST /v1/chat/completions`, SSE) incl. live `hermes.tool.progress` tool rows; `/health` connection check. Sessions are client-side. |
| **Hermes gateway** | REST `https://api-hermes.myrakilabs.com` + WS `wss://hermes.myrakilabs.com/api/ws` | `X-Hermes-Session-Token` header + `?token=` WS param | The full agent gateway: server sessions, resume, tools, skills, JSON-RPC event streaming. **Note:** the current deployment runs gated (`auth_required: true`), which rejects static-token WS auth — this mode needs an ungated gateway or the OAuth/ws-ticket flow (a later phase). |

Unlike the original (which derives the WebSocket address from the REST base URL),
gateway mode configures the two endpoints **independently**. Endpoints persist in
UserDefaults; the credential (API key or session token) lives **only in the macOS
Keychain**. Cloudflare terminates TLS, so the client enforces `https`/`wss` — no
plain `http`/`ws`, no localhost fallback.

### Before first run: verify the endpoints

```sh
curl https://api-hermes.myrakilabs.com/health          # → {"status": "ok", ...}   (v1 mode)
curl https://hermes.myrakilabs.com/api/status           # → real JSON               (gateway mode)
```

An HTML page or 404 means that hostname isn't wired to the service you expect —
catch it in ten seconds instead of an afternoon.

## Configure

1. Launch the app. With no credential saved it boots into the connection-error card.
2. Open **Settings → Gateway** (⌘, or the "Open Settings…" button).
3. Pick the connection mode, confirm the endpoint URL(s), paste your API key (or
   session token in gateway mode), and hit **Test connection** — v1 mode checks
   `/health` and validates the key against `/v1/models`; gateway mode exercises both
   the REST endpoint and the real WebSocket transport.
4. **Save & Reconnect.**

## Build & run

Requires Xcode 26+ (macOS 14+ deployment target). No third-party dependencies.

```sh
open HermesDesktop.xcodeproj          # build & run from Xcode, or:
xcodebuild -project HermesDesktop.xcodeproj -scheme HermesDesktop build
xcodebuild -project HermesDesktop.xcodeproj -scheme HermesDesktop test
```

## Project layout

```
HermesDesktop/
  App/          entry point, connection settings/store, boot + reconnect controller
  Networking/   JSON-RPC WebSocket gateway actor, REST client, Keychain store
  Models/       Codable protocol types (REST + gateway event payloads)
  Design/       design tokens, skin system (light/dark + skin registry)
  Features/
    Shell/      titlebar, sidebar, status bar, empty state, boot overlay
    Chat/       transcript, streaming view model, markdown/code rendering, composer
    Settings/   gateway/connection + appearance screens
HermesDesktopTests/   protocol tests against a mock WebSocket (no network)
reference/            read-only checkout of the original Electron app (gitignored)
```

## Protocol notes

- One JSON object per WebSocket text message (JSON-RPC 2.0); integer request ids;
  responses can arrive out of order (server thread pool) — correlation is strictly
  by id.
- `prompt.submit` is fire-and-forget: the ack can take minutes (30-minute timeout);
  turn completion arrives via streamed events (`message.delta` … `message.complete`).
- Reconnect: deterministic backoff 1/2/4/8/15 s (no jitter), retries forever,
  escalates to a recoverable error overlay after 6 consecutive failures. Wake/network
  restoration triggers an immediate retry. The WS URL is re-derived from settings on
  every attempt.
- The client keys error handling off `error.message` text (matching the reference),
  not JSON-RPC error codes.
