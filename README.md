<div align="center">

# KinoPub for macOS

Native **macOS-only** client for [kino.pub](https://kino.pub), built with SwiftUI, AppKit, AVKit, and AVFoundation. The interface has been reworked for the desktop with an Apple TV-inspired browsing experience.

[![CI](https://github.com/je09/kinopub-mac-client/actions/workflows/ci.yml/badge.svg)](https://github.com/je09/kinopub-mac-client/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/je09/kinopub-mac-client?sort=semver)](https://github.com/je09/kinopub-mac-client/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS-blue)](#requirements)

🌐 **[Website](https://je09.github.io/kinopub-mac-client/)** · 📥 **[Download](https://github.com/je09/kinopub-mac-client/releases/latest)** · 📖 **[Wiki / FAQ](https://github.com/je09/kinopub-mac-client/wiki)**

</div>

> **Community project.** This is an unofficial client and is not affiliated with kino.pub. It uses
> the device-code flow and bundles no user credentials.

## Features

- Reworked Apple TV-inspired interface with full-width heroes, media shelves, and trailer previews
- Native macOS sidebar, toolbar, menus, keyboard shortcuts, Settings window, and system notifications
- Native AVKit player with fullscreen, Picture in Picture, stream quality controls, gesture seeking, system playback controls, and HDR support
- Catalog, collections, bookmarks, history, and Continue Watching
- Search by title, cast, and crew
- Offline MP4 downloads with native download notifications
- Sport channels with multi-source EPG
- 16 interface languages

## Install

Download the latest `.dmg` from [Releases](https://github.com/je09/kinopub-mac-client/releases/latest),
open it, and drag **KinoPub** to Applications. Release builds are ad-hoc signed rather than notarized;
the DMG includes a helper command for removing Gatekeeper quarantine when needed.

An active kino.pub subscription is required. Sign in with the device code shown by the app.

## Requirements

- macOS **13 Ventura** or newer (the project and local packages share this deployment floor)
- Apple Silicon or Intel Mac
- Xcode **16.4+** to build; CI verifies Xcode 16.4 and the pinned Xcode 26.6 release lane

## Building

```bash
git clone https://github.com/je09/kinopub-mac-client.git
cd kinopub-mac-client
open KinoPubAppleClient.xcodeproj
```

Build from Xcode, or run:

```bash
xcodebuild -project KinoPubAppleClient.xcodeproj \
  -scheme KinoPubAppleClient -destination 'platform=macOS' \
  -skipPackagePluginValidation build

./scripts/build-macos.sh  # .app + zip in dist/
./scripts/build-dmg.sh    # drag-to-install DMG in dist/
```

The repository intentionally has an empty `DEVELOPMENT_TEAM`. Choose your own team locally if you
want normal signing; never commit the team identifier.

CI compiles the app with a macOS 13 deployment target on the minimum-Xcode lane and runs the full
suite on the latest lane. Dependabot checks every local package directory explicitly; package
references stored only in the Xcode project (currently KeychainAccess) are monitored manually.

## Project structure

| Package | Purpose |
|---|---|
| `KinoPubAppleClient` | Native macOS application, views, app state, and services |
| `KinoPubUI` | Reusable SwiftUI components |
| `KinoPubKit` | Shared business logic and downloads |
| `KinoPubBackend` | kino.pub API and models |
| `KinoPubLogging` | OSLog helpers |

## Contributing

Issues and PRs are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Conventional Commits drive
Release Please automation.

## License

The upstream project ships no license, so this fork does not relicense it. All rights remain with
the original authors. See [SECURITY.md](SECURITY.md) for vulnerability reporting.
