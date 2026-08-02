<div align="center">

# KinoPub for macOS

Native **macOS** client for [kino.pub](https://kino.pub), built with SwiftUI, AppKit, AVKit, and AVFoundation.

[![CI](https://github.com/dungeon-master-xx/kinopub-apple-client/actions/workflows/ci.yml/badge.svg)](https://github.com/dungeon-master-xx/kinopub-apple-client/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/dungeon-master-xx/kinopub-apple-client?sort=semver)](https://github.com/dungeon-master-xx/kinopub-apple-client/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS-blue)](#requirements)

🌐 **[Website](https://dungeon-master-xx.github.io/kinopub-apple-client/)** · 📥 **[Download](https://github.com/dungeon-master-xx/kinopub-apple-client/releases/latest)** · 📖 **[Wiki / FAQ](https://github.com/dungeon-master-xx/kinopub-apple-client/wiki)**

</div>

> **Community project.** This is an unofficial client and is not affiliated with kino.pub. It uses
> the device-code flow and bundles no user credentials.

## Features

- Native macOS sidebar, toolbar, menus, keyboard shortcuts, Settings window, and system notifications
- Native AVKit player with fullscreen, Picture in Picture, system playback controls, and HDR support
- Catalog, collections, bookmarks, history, and Continue Watching
- Search by title, cast, and crew
- Offline MP4 downloads with native download notifications
- Sport channels with multi-source EPG
- 16 interface languages

## Install

Download the latest `.dmg` from [Releases](https://github.com/dungeon-master-xx/kinopub-apple-client/releases/latest),
open it, and drag **KinoPub** to Applications. Release builds are ad-hoc signed rather than notarized;
the DMG includes a helper command for removing Gatekeeper quarantine when needed.

An active kino.pub subscription is required. Sign in with the device code shown by the app.

## Requirements

- macOS **13 Ventura** or newer
- Apple Silicon or Intel Mac
- Xcode **16+** to build; release automation uses Xcode 26

## Building

```bash
git clone https://github.com/dungeon-master-xx/kinopub-apple-client.git
cd kinopub-apple-client
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
