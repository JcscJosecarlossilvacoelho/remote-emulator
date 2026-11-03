<div align="center">

<img src="docs/icon.png" width="128" alt="Remote Emulator icon" />

# Remote Emulator

**Turn your Mac into a mobile device host for AI agents.**
Let Claude Code, Cursor or any agent on *another machine* drive the iOS simulators and
Android emulators on your Mac — privately, over Tailscale.

[![Build](https://github.com/JcscJosecarlossilvacoelho/remote-emulator/actions/workflows/ci.yml/badge.svg)](https://github.com/JcscJosecarlossilvacoelho/remote-emulator/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift)
![License: MIT](https://img.shields.io/badge/License-MIT-blue)

<img src="docs/screenshot.png" alt="Remote Emulator overview" />

<table>
<tr>
<td><img src="docs/onboarding.png" alt="Guided setup" /></td>
<td><img src="docs/devices.png" alt="Multi-device grid" /></td>
</tr>
<tr>
<td align="center"><b>Guided setup</b> — checks Xcode, Android SDK, Node, agent-device and Tailscale</td>
<td align="center"><b>Multi-device</b> — every simulator & emulator, and which agent uses which</td>
</tr>
<tr>
<td><img src="docs/connect.png" alt="Connect agents" /></td>
<td><img src="docs/app.png" alt="App and Metro" /></td>
</tr>
<tr>
<td align="center"><b>Connect agents</b> — a ready-made prompt your AI agent runs to set itself up</td>
<td align="center"><b>App & Metro</b> — pick your Expo / React Native app, Metro handled for you</td>
</tr>
</table>

</div>

## Why

AI coding agents are great at writing React Native / Expo code, but they need a device to
**see** what they built: tap through flows, take screenshots, read logs. Simulators only run
on macOS, and your agent often doesn't — it lives in a Linux VM, a Windows laptop, a cloud
box or a second Mac.

Remote Emulator is a native macOS app that makes your Mac the device host:

```
 Any machine (Claude Code / Cursor)                     Your Mac (Remote Emulator)
┌───────────────────────────────┐   HTTPS, tailnet only  ┌─────────────────────────────────────┐
│ agent-device CLI / MCP        │ ─────────────────────▶ │ tailscale serve                     │
│ AGENT_DEVICE_DAEMON_AUTH_TOKEN│     bearer token       │  └▶ agent-device proxy 127.0.0.1    │
└───────────────────────────────┘                        │       ├▶ iOS simulators  (Xcode)    │
                                                         │       └▶ Android emulators (SDK)    │
                                                         │ Metro (expo start) ◀── your app     │
                                                         └─────────────────────────────────────┘
```

It is a friendly control panel around [**agent-device**](https://agent-device.dev) by
Callstack (the engine that actually drives the devices) and
[**Tailscale Serve**](https://tailscale.com/kb/1242/tailscale-serve) (the private network).

## Features

- 🪄 **Guided setup** — a 5-step onboarding checks Xcode, Android SDK, Node.js, agent-device
  (one-click install) and Tailscale, starts the host and picks your app. Found an older
  terminal/launchd host? *Take over* archives it and runs everything from the app.
- 🤖 **AI agent prompt** — copy one prompt into Claude Code or Cursor on the other machine and
  the agent installs agent-device, saves the token, connects, registers the MCP server and runs
  a smoke test by itself.
- 📱 **Multi-device** — every iOS simulator and Android emulator on the Mac in one grid.
  Boot / shut down with a click, filter by platform, search, and see **which agent session
  is using which device** right now.
- 🛰 **One-click host** — starts the `agent-device` proxy on `127.0.0.1` and publishes it to
  your tailnet with HTTPS. Detects a host already running from a terminal or launchd.
- 🔐 **Private by default** — never binds to `0.0.0.0`, never uses Funnel/ngrok. A random
  256-bit token (file mode `0600`) protects every route except `/health`. Rotate it anytime.
- 📋 **Copy connect command** — ready-to-paste setup for macOS/Linux, Windows PowerShell or
  Claude Code MCP on the remote machine.
- 📦 **Metro manager** — pick any Expo / React Native app folder, start/stop Metro, see its
  iOS bundle id and Android package, switch between recent apps.
- 🧭 **Menu bar** — keeps serving devices after you close the window; quick status, running
  devices and actions from the menu bar.
- 📜 **Live logs** for the host and Metro, with the token redacted.

## Requirements

| On the Mac (host) | On the agent machine |
|---|---|
| macOS 14+ | Any OS with Node.js ≥ 22.12 |
| Xcode (iOS simulators) and/or Android Studio (emulators) | [Tailscale](https://tailscale.com/download), same tailnet |
| Node.js ≥ 22.12 + `npm i -g agent-device` | `npm i -g agent-device` (same version as the host) |
| [Tailscale](https://tailscale.com/download) with MagicDNS + HTTPS certificates | |

## Install

```sh
git clone https://github.com/JcscJosecarlossilvacoelho/remote-emulator.git
cd remote-emulator
./scripts/build-app.sh --install     # → ~/Applications/Remote Emulator.app
```

Prebuilt, notarized releases are on the roadmap — contributions welcome!

## Quick start

1. **Open Remote Emulator** and follow the setup guide (requirements → host → app → connect).
2. **Boot the devices** you want agents to use (or let agents boot them).
3. Install your app once on each device: Expo Go, or a development build
   (`npx expo run:ios` / `npx expo run:android`).
4. **Connect agents → AI agent prompt → Copy**, and paste it into Claude Code / Cursor on the
   other machine (through a secure channel — it contains the token). The agent does the rest.

Prefer doing it by hand? On the agent machine:

```sh
export AGENT_DEVICE_DAEMON_AUTH_TOKEN='<token>'
export AGENT_DEVICE_SESSION=my-agent
agent-device connect proxy --daemon-base-url https://<your-mac>.<tailnet>.ts.net/agent-device

agent-device devices
agent-device open com.example.app --platform ios
agent-device snapshot -i              # accessibility tree with refs (@e1, @e2…)
agent-device press @e3 --settle       # tap
agent-device screenshot ./screen.png  # downloaded to the agent machine
agent-device close
```

For Claude Code, add the MCP server once:

```sh
claude mcp add --transport stdio --scope user agent-device -- agent-device mcp
```

Several agents can work at the same time: each one uses its own `AGENT_DEVICE_SESSION`, and
agent-device leases a different device to each session. The dashboard shows who holds what.

## Security model

- The proxy listens on **127.0.0.1 only**. Remote access goes exclusively through
  `tailscale serve`, so only devices in **your tailnet** can reach it.
- Every request except `GET /health` needs the bearer token. Treat it like a password:
  anyone holding it can control your simulators. Rotate it from the Remote access card.
- The token lives in `~/.agent-device-host/token` (`0600`) and is redacted from the in-app logs.
- Want stricter rules? agent-device supports a policy file (allowed devices, denied commands):
  see [Remote proxy → Restricting clients](https://agent-device.dev/docs/remote-proxy).

## Files

| Path | What |
|---|---|
| `~/.agent-device-host/token` | Proxy bearer token (shared with terminal setups) |
| `~/.agent-device-host/app-dir` | Active app folder for Metro |
| `~/.agent-device/` | agent-device state, sessions and logs |

## Troubleshooting

| Symptom | Fix |
|---|---|
| *Local only — start Tailscale to share* | Start Tailscale; enable MagicDNS and HTTPS certificates in the admin console. |
| Host shows *Managed outside the app* | A proxy started from a terminal/launchd already owns the port. Stop it there, or keep using it. |
| *Proxy answers but its daemon does not* | The agent-device daemon exits after 5 min idle by default. Remote Emulator starts it with `AGENT_DEVICE_DAEMON_IDLE_TIMEOUT_MS=0` and self-heals; for a host started elsewhere, export that variable before `agent-device proxy`. |
| Remote gets `401` | Token mismatch — copy the connect command again after rotating. |
| Remote gets `REMOTE_SESSION_REQUIRED` | Set `AGENT_DEVICE_SESSION` (or pass `--session`). |
| Android app can't reach Metro | Remote Emulator runs `adb reverse tcp:8081` when Metro starts; restart Metro after booting a new emulator. |
| Expo Go on Android: `Cannot find native module 'ExpoTopicSubscriptionModule'` | Expo Go no longer supports push on Android (SDK 53+). Use a development build. |

## Roadmap

- [ ] Signed & notarized releases + Homebrew cask
- [ ] Create / delete simulators and AVDs from the app
- [ ] Per-device policy editor (allowed commands, read-only agents)
- [ ] Live device thumbnails
- [ ] Physical iOS / Android devices
- [ ] Linux host (Android-only) companion

## Contributing

PRs and issues are very welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

```sh
swift build && swift run RemoteEmulator   # run from source
swift test                                # unit tests
```

## Credits

- [agent-device](https://github.com/callstack/agent-device) by Callstack — the device automation engine.
- [Tailscale](https://tailscale.com) — private networking.
- [Expo](https://expo.dev) — the app framework this was first built for.

Remote Emulator is an independent project, not affiliated with Callstack, Tailscale, Expo or Apple.

## License

[MIT](LICENSE) © 2026 José Coelho
