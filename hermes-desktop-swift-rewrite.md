# Hermes Desktop: the Swift + SwiftUI rewrite

## What this is, in plain terms

The Hermes desktop client exists today as a React and TypeScript app wrapped in Electron. This is a from-scratch rewrite of that same app in native Swift and SwiftUI, same look, same screens, same chat behavior, just a different language underneath. It is not a port in the copy-the-code sense, none of the TypeScript comes across directly, and the original only sticks around as a read-only reference for how things should look and how the network protocol behaves.

There's exactly one deliberate change from the original, and it's worth being clear about because it's the only place this rewrite intentionally diverges: the new app is a pure remote client. It doesn't bundle, install, or babysit a Python backend, and it has no local or SSH mode. It just talks over the network to a Hermes gateway that's already running, reached through your two Cloudflare hostnames. Everything the old Electron main process did around spawning and updating a local backend is dropped. What's kept is only what a network client needs: the connection config, the auth, the API surface, and all the UI.

## The two-endpoint contract, and the one thing to check before running

This is the piece you asked to lock down, so here it is stated plainly and consistently:

- **REST API** lives at `https://api-hermes.myrakilabs.com`, carrying all the `/api/*` calls.
- **WebSocket / chat gateway** lives at `wss://hermes.myrakilabs.com/api/ws`, the JSON-RPC gateway, tunneled to backend port 9119.

Both are editable in Settings, pre-filled with those defaults, persisted in UserDefaults, with the token kept in the Keychain. Auth is the static token: REST sends it as an `X-Hermes-Session-Token` header on every call, the WebSocket appends it as a `?token=` query parameter. Cloudflare terminates TLS, so it's always https and wss, never plain http or ws, and never a localhost fallback.

Here's the one deviation from the original worth understanding, because it's where a bug could hide. The original app assumes REST and WebSocket share a host and derives the WebSocket address from the REST base. This rewrite deliberately breaks that, two separate hostnames, configured independently. That's the correct design for your tunnel setup, but it only holds if `api-hermes.myrakilabs.com` genuinely serves the `/api/*` REST routes. If that hostname routes somewhere that isn't the 9119 service, the WebSocket will connect fine and every REST call will quietly fail, leaving you with a half-working app that's a pain to diagnose.

So before Phase 1 runs its acceptance test, one check settles it:

```
curl -H "X-Hermes-Session-Token: <your-token>" https://api-hermes.myrakilabs.com/api/status
```

Real JSON back means you're clear. HTML or a 404 means that hostname isn't wired to REST, and you've caught it in ten seconds instead of an afternoon.

## The token stays out of the saved prompt

The prompt has Fable 5 ask for the session token at runtime rather than baking it into the file, and that's the right call, leave it that way. The app itself is being built to keep the token in the Keychain and out of logs and UserDefaults, so pasting the live token into a plaintext prompt file would undercut the very rule the app is enforcing. When Fable 5 asks during the live-verification step, hand it over then, for that run only. It never has to live in the saved document.

## How to run it

Same shape as the other rounds:

1. Open the repo in VS Code, fresh Claude Code conversation.
2. `/model fable`, confirm it took.
3. Shift+Tab for plan mode, this rewrite has a Phase 1 checkpoint and you want to see the plan before it commits.
4. Paste the prompt below.
5. Let it run Phase 1, foundation plus a working chat path, and stop for your review, the prompt tells it to. Confirm the chat actually streams before you approve Phase 2.

Have your session token ready for when it asks, and run that curl check first so you know the REST hostname is real before Phase 1 leans on it.

---

## The prompt

```
Build: Hermes Desktop — native Swift + SwiftUI rewrite (remote-only client)

Mission

Recreate the Hermes Agent desktop client — currently an Electron + React app — as a native macOS app in Swift + SwiftUI. The new app must look and behave exactly like the original (same layout, same screens, same visual design, same chat/streaming behavior), with one deliberate architectural change: it is a pure remote client. It does not bundle, install, spawn, or manage a Python backend, and it has no "local" or SSH mode. It connects over the network to an already-running Hermes gateway exposed through Cloudflare tunnels.

This is a from-scratch reimplementation in a new language, not a port. None of the TypeScript/React/Electron code is reusable directly. The original app is provided only as a read-only reference for UI/UX and for the network protocol contract.

Where the reference lives (read-only)

The original Electron/React monorepo is checked out at reference/hermes-agent/ in this repo. It is gitignored and disposable. Read it, do not edit it, do not copy code from it verbatim, do not try to build or run it, and do not add a Python/Node backend to this project.

Read these first, in this order:

1. reference/hermes-agent/apps/desktop/DESIGN.md — the design system. This is your visual spec.
2. reference/hermes-agent/apps/desktop/src/styles.css and .../src/themes/ — the actual CSS custom properties (colors, spacing, shadows) and the theme/skin system. Extract exact values here to match pixel-for-pixel.
3. .../apps/desktop/src/ — the full component tree (app/shell/, app/chat/, components/, app/settings/, app/skills/, store/).
4. .../apps/desktop/src/hermes.ts — the complete REST API client (authoritative endpoint surface).
5. .../apps/desktop/src/types/hermes.ts — all request/response types. Port into Swift Codable.
6. .../apps/shared/src/json-rpc-gateway.ts — WebSocket JSON-RPC client semantics.
7. .../apps/shared/src/websocket-url.ts and .../apps/desktop/electron/connection-config.cjs — WS URL + auth building.
8. .../tui_gateway/server.py — the ~70 JSON-RPC methods (@method("...")).
9. .../tui_gateway/ws.py — the WebSocket wire protocol.
10. .../hermes_cli/web_server.py — REST endpoint implementations (confirm ambiguous shapes here).

The one architectural change: collapse two processes into one

The original is two processes: a React renderer calling window.hermesDesktop.* (Electron IPC), and an Electron main process doing the HTTP/WebSocket I/O, backend discovery, install, and self-update.

In Swift there is only one native process. Every window.hermesDesktop.api({ path, method, body }) becomes a direct URLSession HTTP request. Every gateway interaction becomes a direct URLSessionWebSocketTask. You are not replicating the IPC bridge, and you are dropping entirely all Electron main-process concerns: backend spawn/probe/resolution, first-run bootstrap/install, venv/Python management, native-deps staging, self-update, uninstall, deep-links. Keep only what maps to a network client: connection config, WS-URL building, auth, the API surface, and all UI.

Connection spec (the important change — get this exactly right)

Remote-only over HTTPS/WSS through Cloudflare tunnels. Two independent, separately-configurable endpoints (the original assumes REST and WS share one host:port and derives WS from the REST base — do not carry that assumption over):

- REST API — default https://api-hermes.myrakilabs.com — all /api/* calls.
- WebSocket / chat gateway — default wss://hermes.myrakilabs.com/api/ws — JSON-RPC gateway, Cloudflare tunnel to backend port 9119.

- Both must be editable in Settings (pre-filled with defaults). Persist them (UserDefaults); store the token in the Keychain.
- Auth (token mode — build this):
  - REST: header X-Hermes-Session-Token: <token> + Content-Type: application/json on every request.
  - WebSocket: append ?token=<token> (URL-encoded): wss://hermes.myrakilabs.com/api/ws?token=<token>.
  - Same static session token for both; user supplies it in Settings.
- Cloudflare terminates TLS → always https/wss. No http/ws, no localhost fallback, no SSH.
- Do not build OAuth for v1 (the original's cookie/ticket mode) — structure the connection layer so it could be added later, but implement only the static-token path.
- Surface connection state (connecting/connected/disconnected/needs-setup) with a status pill and reconnect-with-backoff on WS drop (mirror .../app/gateway/hooks/use-gateway-boot.ts).

Protocol spec

REST (https://api-hermes.myrakilabs.com/api/*): plain JSON over HTTP, methods per hermes.ts, token header on every call. >=400 = error; a 2xx body starting with <!doctype/<html> = wrong path (treat as error). Core endpoints first: /api/status, /api/config, /api/profiles/active, /api/profiles, /api/sessions, /api/profiles/sessions, /api/sessions/{id}, /api/sessions/{id}/messages, /api/model/info, /api/model/options, /api/skills, /api/tools/toolsets.

WebSocket (.../api/ws?token=<token>): JSON-RPC 2.0, newline-delimited JSON both ways. On connect, server emits event gateway.ready. Request {"jsonrpc":"2.0","id":<id>,"method":...,"params":{...}}; response matches id with result/error; event {"jsonrpc":"2.0","method":"event","params":{"type":...,"payload":{...},"session_id":...}}. Reimplement correlation/timeout/event-fanout from json-rpc-gateway.ts (an actor over URLSessionWebSocketTask fits). Methods = every @method("...") in server.py; chat-critical: session.create/resume/list/status/history, prompt.submit, session.interrupt/steer, terminal.resize, clarify/approval/sudo/secret.respond. Streaming events to render live: message.start/delta/complete, thinking.delta, reasoning.delta, status.update, tool.start/progress/complete/generating, clarify/approval/sudo/secret.request, background.complete, error, skin.changed (*.delta are high-frequency tokens — coalesce them). prompt.submit is fire-and-forget — completion arrives via streamed events, not the ack; use a long ack timeout and drive UI off events.

UI/UX parity

Visually and behaviorally identical. Build: window shell (custom title bar via .windowStyle(.hiddenTitleBar) + toolbar, traffic-light spacing; sidebar / center / right pane / status bar); collapsible ~236px sidebar (New session ⌘N, Skills & Tools, Messaging, Artifacts; borderless search; PINNED/SESSIONS sections with count badges); empty state (large serif blue "HERMES AGENT" wordmark, rotating subtitle, background wash, docked composer); composer (pill input, + attach, model badge / mic / mute / round send); transcript (user = bordered pill, assistant = plain text, tool calls = gray icon chip with label, inline code mono bg, full markdown + syntax-highlighted code blocks, live streaming, thinking/reasoning); Skills & Tools (tabbed sub-nav, filter chips w/ counts, flat rows + toggles); Settings (incl. the Gateway/Connection screen for the two endpoints + token); onboarding card; overlays (model picker, session picker, ⌘K command palette, toasts, error/boot-failure); status bar (gateway chip, Agents, Cron / token count, session timer). Match spacing, radii, hairlines, elevation, "flat not boxed"; pull exact values from styles.css/themes/. Port the skin system (Shift+X cycles skins, not just light/dark) — light+dark minimum, token system for more. SF Symbols where they match Codicons; note gaps.

Hard constraints — do NOT

- Edit anything under reference/ or copy its source into the app target.
- Add/bundle any Python/Node/Electron backend, installer, bootstrap, venv, or self-updater.
- Implement local/localhost/SSH modes — remote-only.
- Invent API paths, RPC methods, or event types — every one must exist in the reference. If unclear, read web_server.py/server.py; if still unclear, leave a marked // TODO(protocol): and surface it in your summary rather than guessing.
- Put the token in UserDefaults or logs — Keychain only.

Build plan (phased; checkpoint after Phase 1)

Phase 1 — Foundation + working chat (STOP and report after): (1) create the Xcode SwiftUI macOS project (macOS 14+; structure so iPad/iOS is feasible later), folders App/ Networking/ Models/ Design/ Features/; (2) port chat protocol types to Codable; (3) REST client + WS gateway client (actor, gateway.ready, correlation, event stream, reconnect-backoff); (4) Connection/Settings layer (two endpoints + Keychain token + state); (5) app shell + chat surface (empty state, session list, resume→transcript, prompt.submit, live streamed rendering with markdown + code highlighting); (6) verify end-to-end, then stop and report with evidence, protocol TODOs, and a Phase 2 breakdown.

Phase 2+ (after approval): Skills & Tools, full Settings, onboarding, overlays, Messaging/Artifacts, themes/skins parity, then remaining RPC surfaces (cron, pet, billing, spawn tree, voice) to full parity.

Verification / acceptance

App builds cleanly. Each screen visually matches the reference. If the user provides a valid session token, verify live: WS connects (gateway.ready), list sessions, open one, send a prompt, watch tokens stream. No token → unit-test the protocol layer against a mock WebSocket replaying the frame shapes and state that live verification is pending a token. Never claim a screen/flow works without having built and run/previewed it — show evidence.

Deliverables

Buildable Swift+SwiftUI Xcode project at repo root (outside reference/); a short app README.md (what it is, two-endpoint remote model, how to configure endpoints+token, build/run); a Phase 1 completion report. Ask for the session token (and any endpoint corrections) for live verification; otherwise proceed with the defaults and mock-verify.
```
