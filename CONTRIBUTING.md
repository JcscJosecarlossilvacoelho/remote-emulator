# Contributing to Remote Emulator

Thanks for helping! Bug reports, ideas and pull requests are all welcome.

## Run from source

Requirements: macOS 14+, Xcode (Swift 5.10+). No Xcode project needed — it's a Swift package.

```sh
swift build
swift run RemoteEmulator      # opens the dashboard + menu bar item
swift test                    # unit tests
./scripts/build-app.sh        # → dist/Remote Emulator.app (universal, ad-hoc signed)
```

`swift run RemoteEmulator --screenshot docs/screenshot.png` renders the dashboard offscreen
(machine details hidden) — use it to refresh the README screenshot in UI PRs.

## Project layout

```
Sources/RemoteEmulator/
  Core/       Shell (PATH-aware process runner), ManagedProcess, models, ~/.agent-device-host paths
  Services/   DeviceService (simctl / emulator / adb / agent-device claims),
              HostService (agent-device proxy + tailscale serve), MetroService (expo start)
  Views/      SwiftUI dashboard, device grid, menu bar, logs, settings, theme
Tests/        Parsing and model tests
scripts/      App bundle + icon generation
```

## Guidelines

- **Security first.** Never bind the proxy to anything but `127.0.0.1`, never add public
  tunnels (Funnel, ngrok, cloudflared), never log the token.
- **Shell out, don't reimplement.** Device control goes through `xcrun simctl`, `emulator`,
  `adb` and `agent-device` so behaviour matches the official tools.
- **Pure SwiftUI controls** (see `Views/Theme.swift`) so the screenshot renderer keeps working.
- Keep PRs focused, add a test when you touch parsing, and describe how you verified it.

## Good first issues

- Create / delete simulators and AVDs from the device grid
- Show agent-device policy (`AGENT_DEVICE_DAEMON_POLICY`) status in the host card
- Localizations (pt-PT, es, …)
- Homebrew cask + notarized release workflow
