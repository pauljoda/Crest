# Domain

Framework-neutral Swift values, policies and state transitions, one folder
per browser concept. What lives here is what the platform keeps or decides
itself: presentation-side values the core does not own, wire-free message
shapes the adapters translate, and small policies such as memory-pressure
coalescing. Shared browser state and its rules live in CrestCore, not here.

## Goal

Give Application, Infrastructure and the features one vocabulary of typed
values that every platform and engine adapter can use without importing a UI
or system framework.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserAuthentication/` | HTTP sign-in challenges and the decisions that answer them |
| `BrowserCredential/` | Saved-password values: descriptors, scopes, form messages, save candidates, vaults, strong-password generation, Keychain models |
| `BrowserDefaultBrowser/` | How a platform asks to become the default browser |
| `BrowserDownloads/` | Download source capture and feedback events |
| `BrowserFilterLists/` | Content-rule list activation |
| `BrowserGeolocation/` | Geolocation request and position values |
| `BrowserHostedWebNotifications/` | A web notification's delivery and its events |
| `BrowserIdentifiers/` | `StoredIdentity`, the stored spelling of an identity |
| `BrowserNavigation/` | External-scheme prompt answers, navigation response intents, server-trust identity |
| `BrowserPage/` | URL accessors on the core's `PageLiveState` |
| `BrowserPageLifecycle/` | Memory-pressure severity and its coalescer |
| `BrowserPasskeyAccess/` | `BrowserPasskeyPrivacyBoundary`: what passkey access shares across Spaces |
| `BrowserReaderMode/` | Reader state, snapshot and errors |
| `BrowserSession/` | Sidebar selection items and the runtime assignments of tabs and Spaces |
| `BrowserShortcuts/` | Shortcuts, the command catalog and its search document |
| `BrowserSitePermissions/` | Web permission states, system authorization, prompt answers, blocked-popup notices |
| `BrowserSpace/` | Space branding and heraldry, browsing mode, folders, profiles, search providers |
| `BrowserSync/` | iCloud sync diagnostics and conflict summaries |
| `BrowserTab/` | Tab icons, shown titles, native tab content, favicon colour and palette extraction |
| `BrowserTransientBrowsing/` | Quick Window requests, Peek requests and motion, link-pull samples |
| `Text/` | Empty-value helpers on `String` |
| `BrowserWindowState.swift` | A window's sidebar width and visibility on this device |

## Depends on

Foundation only, plus the exact exemptions in
`Config/ArchitectureGuardrails.json`. Consumed by `Application/`,
`Infrastructure/`, `Features/`, the platform trees and the Chromium adapter.

## Rules

- Domain imports Foundation only, apart from entries in `Config/ArchitectureGuardrails.json`; `Scripts/check-architecture.py` enforces it (`Documentation/RepositoryGuardrails.md`, "Architecture and Xcode 27 compatibility").
- Shared browser state and rules belong to the core; only appearance, window geometry and transient presentation stay in Swift (skill, "Architecture"; `Documentation/Architecture/ControlPlane.md`, "What stays in Swift").
- Framework-neutral default-browser and passkey values and policies stay in Domain (`Documentation/RepositoryGuardrails.md`, "Focused guard tests").
- Fixed sets are self-describing types; no `*Policy`, `*Rules` or `*Helper` siblings and no switches on a member (skill, "Code style").
- Identifiers are plain `UUID`; a wrapper exists only for an invariant or behavior (skill, "Architecture").
- Organize by concept, one cohesive concept per file (`Documentation/RepositoryGuardrails.md`, "Feature organization").

## Read next

`Documentation/Architecture/ControlPlane.md` ("What stays in Swift"), then
`.agents/skills/crest-contribution/references/library-style.md` for the type
layout.
