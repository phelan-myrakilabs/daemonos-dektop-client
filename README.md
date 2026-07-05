# Hermes Desktop (Swift)

A native macOS client for the Hermes Agent gateway, written from scratch in Swift +
SwiftUI. It recreates the original Electron/React desktop app — same layout, screens,
visual design, and chat/streaming behavior — with one deliberate architectural change:
**it is a pure remote client**. It does not bundle, install, spawn, or manage a Python
backend, and it has no local or SSH mode. It talks over the network to an
already-running Hermes gateway exposed through Cloudflare tunnels.

## The two-endpoint remote model

Unlike the original (which derives the WebSocket address from the REST base URL), this
client configures the two endpoints **independently**:

| Endpoint | Default | Carries |
|---|---|---|
| REST API | `https://api-hermes.myrakilabs.com` | all `/api/*` calls |
| WebSocket gateway | `wss://hermes.myrakilabs.com/api/ws` | JSON-RPC 2.0 chat gateway (tunneled to backend port 9119) |

Both are editable in **Settings → Gateway** and persisted in UserDefaults. Auth is a
single static session token, stored **only in the macOS Keychain**:

- REST: sent as an `X-Hermes-Session-Token` header on every call.
- WebSocket: appended as a URL-encoded `?token=` query parameter.

Cloudflare terminates TLS, so the client enforces `https`/`wss` — no plain
`http`/`ws`, no localhost fallback.

### Before first run: verify the REST hostname

The split-endpoint design only holds if the REST hostname genuinely serves the
`/api/*` routes. Ten seconds of checking saves an afternoon of debugging:

```sh
curl -H "X-Hermes-Session-Token: <your-token>" https://api-hermes.myrakilabs.com/api/status
```

Real JSON back means you're clear. HTML or a 404 means that hostname isn't wired to
the REST service — the WebSocket will connect fine while every REST call quietly
fails.

## Configure

1. Launch the app. With no token saved it boots into the connection-error card.
2. Open **Settings → Gateway** (⌘, or the "Open Settings…" button).
3. Confirm the two endpoint URLs (pre-filled with the defaults above), paste your
   session token, and hit **Test connection** — it exercises both the REST endpoint
   and the real WebSocket transport (HTTP-only success is a documented false
   positive in the original, so the test requires both).
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
