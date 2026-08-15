# Crest architecture

Crest is a native SwiftUI browser for Apple silicon. It uses WebKit as the browsing engine and treats a **Space** as the primary privacy and organization boundary.

## Source map

```text
CrestShared/
  Application/       Cross-platform coordination and stores
  DesignSystem/      Tokens, reusable components, and modifiers
  Domain/            Value types, policies, and state transitions
  Features/          Shared feature presentation by user purpose
  Infrastructure/    Persistence, WebKit policy, Keychain, and sync
  Resources/         Localizations, privacy manifest, and app icon
CrestMac/             macOS app, WebKit host, commands, and presentation
CrestMobile/          iPhone/iPad app, adaptive chrome, and WebKit host
```

`project.yml` is the target and build-setting source of truth. XcodeGen produces `Crest.xcodeproj`.

## Space isolation

Every persistent Space owns its own browsing state. A Space boundary includes:

- WebKit website data store, cookies, cache, and sessions
- tabs, pinned sites, folders, history, archive, and appearance
- Crest Passwords and credential matching
- content-blocking, permission, and extension state
- synchronization records and deletion tombstones

Private Spaces use non-persistent WebKit storage and do not join normal persistence or sync. Quick Window and Peek are transient presentations, but deliberately borrow the selected Space's session boundary when a signed-in preview is useful.

Space deletion is coordinated across browser state, website data, credentials, sync records, and window restoration. A stale synced record must not resurrect a deleted Space.

## Data and synchronization

Local state is durable first. CloudKit synchronizes portable Space, tab, history, and preference records while secrets remain in the Keychain. Ordered collections use fractional positions so independent devices can insert and reorder without renumbering every record. Merge behavior is deterministic, and deletion wins through tombstones.

Crest can import browser bookmarks and sessions, and its portable archive format keeps migration separate from live CloudKit records. Archive readers validate identifiers and relationships before applying imported state.

## Credentials and privacy

Crest Passwords are stored in the Keychain and matched by origin. Each Space can disable Crest-owned suggestions, generation, save prompts, and HTTP-auth reuse without deleting its stored credentials. Sensitive reveals and exports require device authentication. Page-to-app credential messages are schema-checked and origin-bound.

The privacy manifest is shipped from `CrestShared/Resources/PrivacyInfo.xcprivacy`. Default-browser and browser-passkey capabilities remain gated on Apple approval; no managed entitlement is added speculatively.

## WebKit boundary

Shared infrastructure decides navigation, downloads, content blocking, reader mode, authentication, permissions, failure recovery, and website data ownership. Platform roots provide the actual WebKit view host and native chrome. This keeps policy shared while allowing macOS, iPad, and iPhone to use presentation appropriate to each device.

## Platform shape

macOS and iPad share the same structural model: persistent sidebar, page surface, Space switcher, pinned sites, saved tabs, current tabs, and archive. iPhone presents the same data through compact navigation and sheets rather than forcing desktop chrome into a narrow screen.

The application supports Apple silicon only.

## Validation

Behavior changes begin with a focused regression test. Run the smallest relevant gate, then the affected platform suite. Repository scripts cover identity, cache hygiene, browser fixtures, and release validation. Interactive changes are also exercised in the real macOS app and Simulator.
