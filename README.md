<div align="center">

<img src="docs/assets/icon.png" width="128" height="128" alt="Boaz app icon">

# Boaz

**A calm web browser for iPhone and Mac.**

On iPhone, the page fills the screen and opens where you left it, with your tabs, New Tab and the page menu
within thumb reach and a layout that follows every posture of iPhone Duo. On the Mac, spaces that keep work, home and projects apart. Both stay in step through your private iCloud.

![iOS 27.1+](https://img.shields.io/badge/iOS-27.1%2B-000000?logo=apple)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue)](LICENSE)
[![CI](https://github.com/chenkahana/Boaz/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/chenkahana/Boaz/actions/workflows/ci.yml)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](CONTRIBUTING.md)

[![Download on the App Store](https://img.shields.io/badge/App_Store-iPhone_%26_Mac-6E4BFF?style=for-the-badge&logo=appstore&logoColor=white)](https://apps.apple.com/app/boaz-browser/id6832646304) [![Download for Mac](https://img.shields.io/badge/Download-Boaz.dmg-111111?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/chenkahana/Boaz/releases/latest/download/Boaz.dmg) [![Website](https://img.shields.io/badge/Website-chenkahana.com%2Fboaz-111111?style=for-the-badge&logo=safari&logoColor=white)](https://chenkahana.com/boaz)

[Features](#features) · [Screenshots](#screenshots) · [Architecture](#architecture) · [Getting started](#getting-started) · [Privacy](#privacy) · [Contributing](#contributing)

<img src="docs/assets/hero.png" alt="Boaz on Mac and iPhone" width="900">

</div>

---

## Features

| | |
|---|---|
| **Page first on iPhone** | Boaz opens on the last page you had open. A bar across the bottom holds a fan of your previous tabs (most recent on top), **+** (New Tab) for search and **…** for the page menu; on a folded iPhone Duo they sit in a rail beside the page. Tap the fan for a carousel of your tabs: tap one to open it, swipe one up to archive it. |
| **Spaces on the Mac** | Keep work, home and projects apart. Each space has its own color theme, pinned tabs, folders and favorites. Spaces are a Mac idea; the iPhone shows your tabs without them. |
| **Today and the Archive** | New tabs land in Today. Each device keeps its own Today list, and the iPhone can open the tabs on your Mac. Tabs you haven't opened in a while move to the Archive on their own; pinned tabs stay put. |
| **Search** | Suggestions from your search engine (DuckDuckGo, Google, Bing, Brave, Kagi or Ecosia) mixed with your open tabs, history and address completion. Nothing is sent in Incognito, for addresses, or with suggestions turned off. |
| **Page menu** | Back, Forward, Reload and Share, then Reader, Find on Page, Translate, Listen to Page, text size, desktop or mobile site, and per-site camera, microphone, pop-up and content-blocking settings. |
| **On-device AI** | Summarize Page, Ask This Page and Tidy Tabs, using only Apple's on-device model. Nothing goes to a server. |
| **iCloud sync** | Spaces, pins, folders, favorites and Today sync between iPhone and Mac through your **private** CloudKit database (`CKSyncEngine`). When iCloud is unavailable, a folder you choose works as a fallback. History and Incognito tabs never leave the device. |
| **Built for iPhone Duo** | Folded: the page with the rail beside it, its edges tinted to match the site. Open: a sidebar with search and Today next to the page. Book: sidebar on the left half, page on the right. Laptop: page on top, controls on the lower half. The page is never reloaded as the hinge moves. Standard iPhones get the page with the bar across the bottom. |
| **A full Mac browser** | Sidebar with spaces, command bar (⌘T / ⌘L), split view, rebindable shortcuts, downloads, and a small Quick Window for links opened from other apps. |
| **Bring Arc with you** | On Mac, import Arc's spaces, pinned folders, favorites, themes, keyboard shortcuts and, if you opt in, cookies as they are. Chrome, Brave, Edge and Safari bookmarks import too. |
| **Private by design** | Built-in ad and tracker blocking (EasyList), cookie-banner declining on iPhone, Incognito tabs and a reader view. No accounts, analytics or third-party SDKs. |
| **System integration** | Share extension ("Add to Boaz"), a search widget, App Shortcuts ("Open in Boaz", "Search in Boaz"), the `boaz://` URL scheme, a default-browser handler on Mac, and alternate app icons. |

## Screenshots

iPhone Duo, folded:

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/duo-1-page.png" alt="A page with the rail beside it" width="210"><br><sub>The page and the rail</sub></td>
    <td align="center"><img src="docs/screenshots/duo-2-tabs.png" alt="The tab carousel" width="210"><br><sub>Your tabs</sub></td>
    <td align="center"><img src="docs/screenshots/duo-3-search.png" alt="Search with suggestions" width="210"><br><sub>Search</sub></td>
    <td align="center"><img src="docs/screenshots/duo-4-menu.png" alt="The page menu" width="210"><br><sub>Page menu</sub></td>
  </tr>
</table>

iPhone:

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/iphone-63-1-page.png" alt="A page with the bar across the bottom" width="190"><br><sub>The page</sub></td>
    <td align="center"><img src="docs/screenshots/iphone-63-2-tabs.png" alt="The tab carousel" width="190"><br><sub>Your tabs</sub></td>
    <td align="center"><img src="docs/screenshots/iphone-63-3-search.png" alt="Search with suggestions" width="190"><br><sub>Search</sub></td>
    <td align="center"><img src="docs/screenshots/iphone-63-4-menu.png" alt="The page menu" width="190"><br><sub>Page menu</sub></td>
  </tr>
</table>

iPhone Duo, open:

<img src="docs/screenshots/duo-5-open.png" alt="Unfolded: the sidebar with search and Today next to the page" width="640">

Mac:

<table>
  <tr>
    <td><img src="docs/screenshots/mac-1-personal.png" alt="Boaz for Mac, Personal space" width="290"></td>
    <td><img src="docs/screenshots/mac-2-work.png" alt="Boaz for Mac, Work space" width="290"></td>
    <td><img src="docs/screenshots/mac-3-travel.png" alt="Boaz for Mac, Travel space" width="290"></td>
  </tr>
</table>

## Architecture

Boaz is two native SwiftUI apps over one shared Swift package. All app targets compile in Swift 6 language mode with
main-actor default isolation; database and sync work runs off the main actor.

```mermaid
flowchart LR
    subgraph iPhone
        iOS[Boaz for iPhone] --- Share[Share extension]
        iOS --- Widgets[Widgets]
    end
    Mac[Boaz for Mac]
    subgraph BoazKit[BoazKit · Swift package]
        Store[(Library store<br/>GRDB · SQLite)]
        Sync[Sync engine<br/>CKSyncEngine · folder fallback]
        Import[Importers<br/>Arc · bookmarks]
    end
    iOS --> BoazKit
    Share --> Store
    Widgets --> Store
    Mac --> BoazKit
    Sync <--> CloudKit[(Private iCloud database)]
```

| Layer | Path | What it holds |
|---|---|---|
| iPhone app | [`Apps/iOS`](Apps/iOS) | App model, posture-aware shell, tab browser, rail and tab carousel, bottom panels, reader, onboarding, App Intents |
| Mac app | [`Apps/macOS`](Apps/macOS) | Window and sidebar, command bar, key bindings, Arc import UI, onboarding |
| Extensions | [`Apps/Extensions`](Apps/Extensions) | Share extension and WidgetKit widgets |
| Shared UI | [`Apps/Shared`](Apps/Shared) | Theme, assets, onboarding content, privacy manifest |
| Web engine glue | [`Apps/Browser`](Apps/Browser) | WebKit content blocking, downloads, favicons, site colors, search suggestions, on-device AI |
| Core | [`Packages/BoazKit`](Packages/BoazKit) | Records, store and migrations, CloudKit and folder sync, Arc and bookmark importers |

More detail: [docs/architecture.md](docs/architecture.md).

## Getting started

### Requirements

- macOS 26 or later with **Xcode 27.2** (iOS 27.1 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- For simulators and `make build`, nothing else: builds are unsigned. To run on a device or test sync, use your own
  Apple Developer team: replace `DEVELOPMENT_TEAM` and the `com.chenkahana` identifiers in `project.yml` locally (don't commit them),
  and create a matching iCloud container and app group

### Build and run

```bash
git clone https://github.com/chenkahana/Boaz.git
```

```bash
cd Boaz && make bootstrap
```

```bash
open Boaz.xcodeproj
```

Pick the **Boaz-iOS** scheme with an iPhone Duo simulator, or **Boaz-macOS** for the Mac app. The Xcode project is
generated from [`project.yml`](project.yml) and isn't checked in; run `make project` after changing targets, files
or settings.

### Common tasks

| Command | What it does |
|---|---|
| `make bootstrap` | Checks the toolchain, installs XcodeGen if missing, generates the project |
| `make project` | Regenerates `Boaz.xcodeproj` from `project.yml` |
| `make build` | Builds BoazKit and both apps without code signing (what CI runs) |
| `make archive` | Builds signed Release archives for App Store Connect into `build/archives` |
| `make clean` | Removes build output |

## Repository layout

```
Boaz/
├── Apps/
│   ├── iOS/              iPhone app
│   ├── macOS/            Mac app
│   ├── Extensions/       Share extension, widgets
│   ├── Browser/          WebKit glue shared by both apps
│   └── Shared/           Theme, assets, privacy manifest
├── Packages/BoazKit/    Core library: model, store, sync, importers
├── Tools/                Icon generator and release scripts
├── docs/                 Architecture, privacy policy, release guide, screenshots
├── .github/              CI, issue and pull-request templates
├── project.yml           XcodeGen project definition
└── Makefile              Developer entry points
```

## Privacy

Boaz collects no data. Your library syncs only through your own private iCloud database, and history stays on the
device. The full policy is in [docs/privacy.md](docs/privacy.md); each app ships a privacy manifest
([`PrivacyInfo.xcprivacy`](Apps/Shared/PrivacyInfo.xcprivacy)).

## Releasing

Versioning, archives, App Store metadata and the review checklist are in [docs/app-store.md](docs/app-store.md).
Changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## Contributing

Contributions are welcome, from a typo fix to a new feature.

- Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, conventions and the review checklist.
- Looking for a place to start? Try an issue labelled
  [`good first issue`](https://github.com/chenkahana/Boaz/labels/good%20first%20issue) or
  [`help wanted`](https://github.com/chenkahana/Boaz/labels/help%20wanted).
- Found a bug? Open a [bug report](https://github.com/chenkahana/Boaz/issues/new?template=bug_report.yml).
- Security issues go through [SECURITY.md](SECURITY.md), never public issues.
- Questions: see [SUPPORT.md](SUPPORT.md).

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## The family

Boaz, Jimmy and Edison are made by one independent developer, on the same principles: native Swift and SwiftUI,
private by design (no accounts, analytics or tracking), and open source under the Mozilla Public License 2.0.

<table>
  <tr>
    <td align="center" width="33%"><a href="https://github.com/chenkahana/Boaz"><img src="https://raw.githubusercontent.com/chenkahana/Boaz/master/docs/assets/icon.png" width="88" alt="Boaz app icon"></a><br><b><a href="https://github.com/chenkahana/Boaz">Boaz</a></b><br><sub>A calm web browser for iPhone and Mac</sub></td>
    <td align="center" width="33%"><a href="https://github.com/chenkahana/Jimmy"><img src="https://raw.githubusercontent.com/chenkahana/Jimmy/main/docs/assets/icon.png" width="88" alt="Jimmy app icon"></a><br><b><a href="https://github.com/chenkahana/Jimmy">Jimmy</a></b><br><sub>A queue-centric podcast player for iPhone</sub></td>
    <td align="center" width="33%"><a href="https://github.com/chenkahana/Edison"><img src="https://raw.githubusercontent.com/chenkahana/Edison/main/docs/assets/icon.png" width="88" alt="Edison app icon"></a><br><b><a href="https://github.com/chenkahana/Edison">Edison</a></b><br><sub>Clipboard history and screenshots for Mac</sub></td>
  </tr>
</table>

<p align="center"><sub>More at <a href="https://chenkahana.com">chenkahana.com</a></sub></p>

## License

Copyright © 2026 Chen Kahana. Boaz is licensed under the [Mozilla Public License 2.0](LICENSE).
Third-party components and their licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Arc is a trademark of The Browser Company. Boaz is an independent project, not affiliated with or endorsed by The
Browser Company; it only reads Arc's files on your Mac when you choose to import them.
