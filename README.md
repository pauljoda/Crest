<div align="center">
  <img src="Website/assets/crest-logo.svg" width="128" alt="Crest app icon">
  <h1>Crest</h1>
  <p><strong>Your internet, under your colors.</strong></p>
  <p>A native browser for Apple silicon where every part of your life gets its own Space—and every Space keeps its own world.</p>
  <p>
    <a href="https://crestbrowser.com/"><strong>Visit the product site</strong></a>
    ·
    <a href="https://crestbrowser.com/guides/">Read the guides</a>
    ·
    <a href="https://github.com/pauljoda/Crest/releases">Download for Mac</a>
    ·
    <a href="Documentation/ROADMAP.md">Roadmap</a>
  </p>
</div>

![Crest open to the Personal Space, with its banner-colored sidebar and pinned sites](Website/assets/crest-personal-mac-clean.png)

## A browser with boundaries

Most browsers put every login, tab, and distraction into one long-lived container. Crest begins with **Spaces** instead. Give work, home, research, or a private session its own banner; Crest gives each one its own cookies, website data, history, archive, tabs, credentials, settings, and sync identity.

Switching Spaces changes more than the color of the window. It changes the browsing context.

## What makes Crest different

- **Spaces with real separation** — sessions, cookies, cache, history, tabs, pins, passwords, extensions, and synchronization remain within their Space.
- **A banner for every side of you** — layer color, field, emblem, and trim into a visual identity that makes context recognizable at a glance.
- **Quick Window** — open a focused, transient page with the right Space's signed-in session, then dismiss it without feeding the main tab pile.
- **Peek** — preview a link above the current page and decide whether it deserves a permanent tab.
- **A calmer sidebar** — pinned sites, folders, saved tabs, current tabs, recent tabs, downloads, and archive have distinct jobs.
- **Crest Passwords** — origin-matched credentials live in the Keychain, with device authentication around sensitive access and export.
- **Private Spaces** — non-persistent WebKit storage with no normal history, restoration, or sync trail.
- **Native everywhere** — SwiftUI chrome shaped for macOS, iPad, and iPhone, backed by WebKit rather than a cross-platform shell.
- **Power when it helps** — reader mode, content blocking, downloads, website permissions, authentication challenges, popup handling, recovery, and keyboard customization.
- **Portable by design** — import browser data, export a validated Crest archive, and synchronize durable state through CloudKit.

## Built as an Apple-platform app

Crest is written in Swift and SwiftUI. Shared policies and features live in `CrestShared`; each platform owns its actual window, WebKit host, commands, and adaptive presentation.

```text
CrestShared/   Domain, application, infrastructure, features, design system
CrestMac/      macOS app and platform-specific presentation
CrestMobile/   iPhone and iPad app and platform-specific presentation
```

Read [the architecture overview](Documentation/ARCHITECTURE.md) for Space isolation, persistence, credentials, synchronization, and the WebKit boundary.

## Build Crest

Requirements:

- Apple silicon Mac
- Xcode with the macOS 26 and iOS 26 SDKs
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
git clone https://github.com/pauljoda/Crest.git
cd Crest
Scripts/bootstrap.sh
open Crest.xcodeproj
```

`project.yml` is the source of truth for targets and build settings. Run `xcodegen generate` after changing source roots, targets, or project configuration.

## Releases and updates

macOS releases are distributed directly through GitHub Releases as signed,
notarized Apple-silicon disk images. Crest uses Sparkle 2 with a native SwiftUI
update interface. Stable and nightly builds share a signed appcast; joining the
nightly channel is an explicit choice in General Settings.

GitHub Actions builds every public release, verifies its Developer ID signature
and notarization, publishes provenance and checksums, then updates the signed
`updates` branch appcast only after the immutable release assets exist. Public
downloads live in GitHub Releases rather than GitHub Packages. See the
[distribution runbook](Documentation/Distribution.md) for the channel,
credential, publication, and verification contracts.

## Validate a change

```bash
Scripts/validate-identity.sh
Scripts/validate.sh
Scripts/validate-cache-hygiene.sh
```

Behavior changes should begin with a focused regression test, followed by the affected platform suite. Interactive work is exercised in the real app and Simulator as well as through automated gates.

## Project status

Crest is under active development. The current implementation includes the core browsing, Space isolation, native platform chrome, credentials, data portability, synchronization foundations, Quick Window, Peek, and privacy features described above. Approval-gated and physical-device release work is tracked in the [roadmap](Documentation/ROADMAP.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and change discipline. Architecture changes should preserve the Space boundary and the native shape of each platform.

## License and brand

Crest source code is available under the [Mozilla Public License 2.0](LICENSE).
The source is open for inspection, modification, and commercial use under that
license. The Crest name, app icon, logos, and official distribution identity
are reserved; modified distributions must use their own branding as described
in [TRADEMARKS.md](TRADEMARKS.md). Third-party notices are collected in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
