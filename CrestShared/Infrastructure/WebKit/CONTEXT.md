# WebKit

WebKit's binding, shared by the Mac, iPhone and iPad. `WebKitEngineBinding`
builds each page the core asks WebKit to create, performs the core's engine
commands, raises sign-ins, script dialogs and permission requests with the
core, runs WebKit's downloads, keeps each profile's website data store, and
compiles Crest's content rules. Platform hosting of the web view stays in
`CrestMac/Infrastructure/WebKit/` and `CrestMobile/Infrastructure/WebKit/`.

## Goal

WebKit behaves as one engine behind the shared engine port, reporting what
happened and deciding no browser rule itself.

## Contents

| Path | What it is |
| --- | --- |
| `WebKitEngineBinding.swift`, `WebKitEnginePage.swift`, `WebKitEnginePages.swift`, `WebKitPageHosting.swift`, `BrowserWebKitPageEngine.swift` | The binding, its pages, the direct platform path to them, and the page engine adapter |
| `Commands/` | One `<Command>+WebKitEngineBinding.swift` per engine command, each performing itself on the binding |
| `Requests/` | One `<Request>+WebKitEnginePages.swift` per page request, each answering itself from WebKit's pages |
| `Prompts/` | Sign-ins, script dialogs and permission requests waiting on the core's answer |
| `Navigation/` | Navigation gates, external schemes, server trust, popup triggers |
| `Popups/` | Popup routing, window features and the blocked-popup bridge |
| `ContentBlocking/` | Content-rule compilation and one page owner's content blocking |
| `Credentials/` | The credential session and bridge delivered through WebKit's user content controller |
| `Downloads/` | WebKit downloads run as the engine's own, automatic-download requests, replay |
| `WebsiteData/` | Per-profile website data stores and their removal |
| `Agents/` | What an allowed agent's scripts and activity observer do in WebKit pages |
| `Favicons/` | Favicon capture from a WebKit document |
| `Find/` | Find-in-page over `WKWebView` |
| `Geolocation/` | The Core Location-backed Geolocation bridge and its messages |
| `MediaSessions/` | The Media Session bridge and media-activity reports |
| `ReaderMode/` | The Reader document and controller |
| `SitePermissions/` | WebKit's permission and origin spellings |
| `Translation/` | The translation document in WebKit's content world |
| `UserActivity/` | The user-activity bridge |
| `PlatformPage+*.swift` | Content policy, media sessions, sign-in, site permissions and navigation on a platform page |
| `BrowserLinkPull*.swift` | Decoding the link-pull bridge for Peek |
| `WebKitPopup.swift`, `WebKitSignInResponder.swift` | A popup WebKit makes from its opener's configuration; a sign-in answered through the core |
| `BrowserTransientPageLease.swift`, `BrowserPageHost+TransientLeases.swift` | Quick Window and Peek page leases |
| `BrowserPageContentRuleSession.swift`, `BrowserPageNavigationHistory.swift`, `BrowserPageOwner+ScriptMessages.swift`, `ScriptMessageProxy.swift` | Crest's content rules on a page, its back/forward lists, and content-bridge messages |
| `PageConfiguration.swift`, `PageSecurity+WebKit.swift`, `VisitedLinkStyler.swift` | Page configuration defaults, WebKit's security judgment, visited-link styling |
| `BrowserAppPreferenceStore+WebKitSpelling.swift`, `BrowserMacWebTextAssistancePreference.swift` | Spelling and text-checking preferences WebKit reads |

## Depends on

WebKit, `Engines/` (the port it implements), `Core/` (commands, requests,
reports), `Application/` and `Domain/`. Consumed by the Mac and mobile page
hosts and compositions.

## Rules

- The binding reports what WebKit did and settles what the core answers; it never decides browser rules or changes state except by reporting (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- A command performs itself in `Commands/` (`perform(on:)`) and a page request answers itself in `Requests/` (`answer(on:)`); a new case without its logic does not compile (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- On the Mac a popup window opens as a Quick Window in its opener's engine and Space, never a new window; iPhone and iPad have no Quick Window and open it as a tab (`Documentation/LinkOpeningPolicy.md`, "Link opening"; skill, "Windows and UI").
- A Space is one profile; private profiles get a non-persistent store erased when private browsing ends (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership"; `Documentation/Architecture/ControlPlane.md`, "WebKit's binding").
- Content-blocking rules are decided by the core; WebKit only compiles and applies them (`Documentation/Architecture/ContentBlocking.md`, "Built-in protection").
- Reader and built-in content blocking are WebKit-only by decision (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- No SwiftUI here (`Scripts/check-architecture.py`; `Documentation/RepositoryGuardrails.md`, "Architecture and Xcode 27 compatibility").

## Read next

`Documentation/Architecture/ControlPlane.md` ("WebKit's binding", "Page
lifecycle"), `Documentation/Architecture/EngineAbstractionCompletion.md`
("How each engine behaves"), then `../Engines/CONTEXT.md`.
