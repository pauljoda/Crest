# Routing: what to read for each kind of change

Crest is more than a contributor or a coding agent can hold
at once. Find the row for the change, open what it names, and skip what it
says to skip. Each `CONTEXT.md` is a short map of one folder: what it owns,
its children, what it depends on, and its rules, each pointing to the full
text. The rules themselves live in `AGENTS.md`, the `crest-contribution`
skill and `Documentation/`; these files only route to them.

The layout follows the Interpretable Context Methodology
([arXiv 2603.16021](https://arxiv.org/html/2603.16021v2)): a routing table
plus one context file per folder that groups work.

Reading order: this table, then the root [`CONTEXT.md`](CONTEXT.md), then the
`CONTEXT.md` of the folder you change, then everything in the row's Load
column.

## Core (.NET)

| Task | Go to | Load | Skip |
| --- | --- | --- | --- |
| Shared tab, Space, window or history behavior | `CrestCore/CONTEXT.md` | `Documentation/Architecture/CoreArchitecture.md`, `CrestCore/README.md` | Swift views until the core intent exists |
| A new or changed core contract (intent, change, query, event) | `CrestCore/src/CrestCore/Contracts/CONTEXT.md` | `Documentation/Architecture/ControlPlane.md`, then run `Scripts/control-plane/generate-contracts.sh` | hand edits to any `Generated` file |
| An engine command or event contract | `CrestCore/src/CrestCore/Contracts/CONTEXT.md` | the Chromium inputs row below: it regenerates `CrestContracts/include/crest_engine_contract.h`, an engine input | |
| A session intent (tabs, folders, splits, Spaces, history, imports) | `CrestCore/src/CrestCore/Application/Session/CONTEXT.md` | `Documentation/Architecture/ControlPlane.md` ("Sessions and commands"), the `Intents/` subfolder for the change | `CrestCore/src/CrestCore/Application/Sync/`, Swift views |
| What a window shows, per-site engines, shortcuts, link routes, setup | `CrestCore/src/CrestCore/Application/Device/CONTEXT.md` | `Documentation/Architecture/ControlPlane.md` ("Windows belong to the device"), `Documentation/LinkOpeningPolicy.md` | `CrestCore/src/CrestCore/Application/Session/Intents/` |
| Page lifecycle, navigation recording, offered popups, rehosting | `CrestCore/src/CrestCore/Application/Pages/CONTEXT.md` | `Documentation/Architecture/ControlPlane.md` ("Page lifecycle") | the engine bindings until the core rule exists |
| Importing from another browser, or an export format | `CrestCore/src/CrestCore/Application/Portability/CONTEXT.md` | `Documentation/ARCHITECTURE.md` ("Data and synchronization"), `CrestCore/tests/CrestCore.Tests/Portability/` | `CrestCore/src/CrestCore/Application/Sync/` |
| Downloads (policy, progress, destinations) | `CrestCore/src/CrestCore/Application/Downloads/CONTEXT.md` | `CrestShared/Infrastructure/Downloads/`, `CrestShared/Features/Utilities/CONTEXT.md` | other features |
| A generator emitter or the wire codec | `CrestCore/tools/CrestCore.Generator/CONTEXT.md` | `Documentation/Architecture/ControlPlane.md` ("The typed contract"), `Scripts/control-plane/generate-contracts.sh` | hand edits to any generated output |
| A native entry point (`crest_app_*`, `crest_engine_*`) | `CrestCore/src/CrestCore.Native/CONTEXT.md` | `CrestContracts/README.md`, `Documentation/Architecture/ControlPlane.md` ("The C ABI") | `Generated/` |
| Content blocking | `Documentation/Architecture/ContentBlocking.md` | `CrestCore/src/CrestCore/Application/ContentBlocking/`, the page adapter | other features |
| Credentials and passkeys | `CrestCore/src/CrestCore/Application/Credentials/CONTEXT.md` | `Documentation/ARCHITECTURE.md` ("Credentials and privacy"), `CrestShared/Features/Credentials/CONTEXT.md`, `CrestShared/Infrastructure/Credentials/` | |
| Sync and persistence | `CrestCore/src/CrestCore/Application/Sync/CONTEXT.md` | `Documentation/ARCHITECTURE.md` ("Data and synchronization"), `CrestShared/Infrastructure/Sync/` | UI features |

## Shared Swift

| Task | Go to | Load | Skip |
| --- | --- | --- | --- |
| A shared UI feature not listed below | `CrestShared/Features/CONTEXT.md` | the feature folder, `CrestShared/DesignSystem/CONTEXT.md` before any new control | CrestCore internals |
| Sidebar rows, folders, the Space header or drag and drop | `CrestShared/Features/Sidebar/CONTEXT.md` | `Documentation/ARCHITECTURE.md` ("Platform shape"), `CrestMac/Features/Sidebar/`, `CrestMobile/Features/Sidebar/` | CrestCore internals until an intent is needed |
| A settings pane or destination | `CrestShared/Features/Settings/CONTEXT.md` | `CrestShared/Features/Settings/Models/BrowserSettingsDestination.swift`, the pane's folder, `CrestMac/Features/Settings/` or `CrestMobile/Features/Settings/` | `CrestShared/Resources/` asset catalogs |
| Peek or Quick Window UI | `CrestShared/Features/TransientBrowsing/CONTEXT.md` | `Documentation/LinkOpeningPolicy.md`, `CrestShared/Application/BrowserTransientBrowsing/` | other features |
| The command palette or address field | `CrestShared/Features/Chrome/CONTEXT.md` | `CrestShared/Features/Chrome/Components/BrowserCommandPalette/`, `Documentation/ARCHITECTURE.md` ("Engine boundary") | the engine adapters |
| Split view layout | `CrestShared/Features/SplitView/CONTEXT.md` | `Documentation/NativeTabs.md`, `CrestMac/Features/SplitView/`, `CrestMobile/Features/SplitView/` | |
| Browser data import or export | `CrestShared/Features/DataPortability/CONTEXT.md` | `Documentation/ARCHITECTURE.md` ("Data and synchronization"), `CrestCore/src/CrestCore/Application/Portability/` | sync transport |
| Archive, History or Downloads lists | `CrestShared/Features/Utilities/CONTEXT.md` | `CrestShared/Infrastructure/Downloads/`, `CrestShared/Features/Sidebar/Services/BrowserSidebarUtilityCoordinator.swift` | |
| A design-system control, style or token | `CrestShared/DesignSystem/CONTEXT.md` | `CrestShared/DesignSystem/Components/CrestControlsGallery.swift`, the skill ("Windows and UI") | feature views until the component exists |
| A window action or a new `BrowserStore` intent call | `CrestShared/Application/BrowserStore/CONTEXT.md` | `Documentation/Architecture/ControlPlane.md` ("The read model") | feature presentation |
| Applying a new core change to the Swift read model | `CrestShared/Infrastructure/Core/CONTEXT.md` | `CrestShared/Infrastructure/Core/Changes/`, `Documentation/Architecture/ControlPlane.md` ("The typed contract", "The read model") | hand edits to `CrestShared/Infrastructure/Core/Generated/` |
| A WebKit engine command or page request | `CrestShared/Infrastructure/WebKit/CONTEXT.md` | `CrestShared/Infrastructure/WebKit/Commands/`, `CrestShared/Infrastructure/WebKit/Requests/`, `Documentation/Architecture/ControlPlane.md` ("WebKit's binding") | `CrestEngines/Chromium/` |
| A new engine capability or registration | `CrestShared/Infrastructure/Engines/CONTEXT.md` | `Documentation/Architecture/EngineAbstractionCompletion.md` ("Ownership decision guide") | `CrestEngines/Chromium/Overlay/`, `CrestEngines/Chromium/Patches/` |
| Strings, app icon variants, emoji or SF Symbol catalogs | `CrestShared/Resources/CONTEXT.md` | `Scripts/generate-emoji-catalog.py`, `Scripts/update-sf-symbol-catalog.py`, `Scripts/generate-app-icon-palettes.py` | app source |

## Mac

| Task | Go to | Load | Skip |
| --- | --- | --- | --- |
| Mac windows, menus, the Dock, launch recovery or quit | `CrestMac/App/CONTEXT.md` | `Documentation/ARCHITECTURE.md` ("Windows on macOS"), `CrestMac/App/Shell/BrowserMacShell.swift`; for the Dock tile icon, `CrestDockTilePlugin/CONTEXT.md` | CrestMobile, `CrestMac/App/Composition/` |
| A Mac page, the page pool or an engine event | `CrestMac/Infrastructure/Pages/CONTEXT.md` | `Documentation/ARCHITECTURE.md` ("Engine boundary"), `CrestMac/Infrastructure/Pages/EngineEvents/BrowserPageEngineEvent.swift` | `CrestEngines/Chromium/Overlay/`, `CrestEngines/Chromium/Patches/` |
| Mac WebKit page behavior (delegates, link bridges, Picture in Picture, feature flags) | `CrestMac/Infrastructure/WebKit/CONTEXT.md` | `CrestShared/Infrastructure/WebKit/`, `Documentation/Architecture/DesktopPictureInPicture.md` | the Chromium fork |
| Quick Window or a popup window | `CrestMac/Features/QuickWindow/CONTEXT.md` | `Documentation/LinkOpeningPolicy.md`, `HelpCenter/docs/browsing/peek-and-quick-window.md` | CrestMobile |
| Mac setup or importing from another browser | `CrestMac/Features/Onboarding/CONTEXT.md` | `Documentation/ARCHITECTURE.md` ("Data and synchronization"), `CrestShared/Features/Onboarding/` | Settings panes |
| A Mac-only Settings pane (engines, agents, shortcuts, system privacy) | `CrestMac/Features/Settings/CONTEXT.md` | `Documentation/NativeTabs.md`, `CrestShared/Features/Settings/` | CrestMobile |
| Link opening and popups (the policy) | `Documentation/LinkOpeningPolicy.md` | `CrestMac/Features/QuickWindow/CONTEXT.md` | |
| The agent bridge (MCP tools) | `CrestAgents/CONTEXT.md` | `CrestMac/App/Agents/`, `CrestMac/Infrastructure/Agents/`, `CrestAgentHelper/CONTEXT.md`, `HelpCenter/docs/browsing/coding-agents.md` | CrestMobile |

## iPhone and iPad

| Task | Go to | Load | Skip |
| --- | --- | --- | --- |
| An iPhone or iPad layout, gesture or presentation | `CrestMobile/CONTEXT.md` | `Documentation/ARCHITECTURE.md` ("Scenes on iPhone and iPad", "Platform shape"), the same-named folder in `CrestShared/Features/` | CrestMac, `CrestEngines/` |
| The mobile browser root (compact and regular layout, tab or history swipe, page surface) | `CrestMobile/Features/Browser/CONTEXT.md` | `CrestMobile/Features/Browser/MobileBrowserRootView/Models/MobileBrowserRootModel.swift` | `CrestShared/Features/Settings/` |
| The mobile WebKit page or an iOS system service (default browser, share link, passkeys, CloudKit) | `CrestMobile/Infrastructure/CONTEXT.md` | `Documentation/Architecture/EngineAbstractionCompletion.md` ("Ownership"), `CrestMobile/Infrastructure/WebKit/MobileBrowserPageStore.swift` | the Chromium fork |

## Engines

| Task | Go to | Load | Skip |
| --- | --- | --- | --- |
| Chromium engine inputs (patches, overlay, host header, prepare/apply/configure/build scripts) | `CrestEngines/Chromium/CONTEXT.md` | `CrestEngines/Chromium/README.md` ("Releasing"), `CrestEngines/Chromium/ForkMaintenance.md` | CrestMobile, `HelpCenter/` |
| The Chromium C++ binding or the Crest BrowserWindow (an engine input) | `CrestEngines/Chromium/CONTEXT.md` ("Overlay") | `CrestEngines/Chromium/README.md` ("Native Crest host overlay", "Releasing"), `Documentation/Architecture/CoreArchitecture.md` ("Engines") | CrestMobile, `CrestEngines/Chromium/Apple/EnginePresentations/` |
| How a Chromium engine event or extension UI appears in Swift | `CrestEngines/Chromium/Apple/CONTEXT.md` | `CrestEngines/Chromium/Apple/EnginePresentations/`, `CrestEngines/Chromium/Apple/Extensions/` | `CrestEngines/Chromium/Overlay/`, `Patches/` |

## Tests, tooling, docs and release

| Task | Go to | Load | Skip |
| --- | --- | --- | --- |
| A new or changed permanent test | `CrestTests/CONTEXT.md` (`CrestMobileTests/CONTEXT.md` for mobile-only adapters) | the skill ("Tests"), `AGENTS.md` ("Test retention and cleanup") | appearance, layout and copy |
| A repository check, validation or release script | `Scripts/CONTEXT.md` | `Documentation/RepositoryGuardrails.md`, `Scripts/Tests/CONTEXT.md` | app source |
| Core build, contract generation, or Chromium build and publish tooling | `Scripts/control-plane/CONTEXT.md` | `Documentation/Architecture/ControlPlane.md` ("Build workflow"), `CrestEngines/Chromium/README.md` ("Releasing") | Swift features |
| A Help Center guide | `HelpCenter/CONTEXT.md` | the guide under `HelpCenter/docs/`, `HelpCenter/static/img/guides/README.md` | `Website/guides/` (build output) |
| A third-party dependency or notice | `ThirdParty/CONTEXT.md` | `Config/ThirdPartyDependencies.json`, `Scripts/audit-licenses.py` | app source |
| Build settings or targets | `project.yml` | `CONTRIBUTING.md` ("Local setup"), `Config/CONTEXT.md` | `Crest.xcodeproj` (generated by XcodeGen) |
| A version bump or release note | `AGENTS.md` ("Versioning completed work", "Explicit release notes") | `Config/Version.xcconfig`, `Documentation/ReleaseNotes.json` | everything else |
| Website copy | `Website/CONTEXT.md` | the page being changed | the app source, `Website/guides/` (built from `HelpCenter/`) |

## Always

- `AGENTS.md` and the `crest-contribution` skill: the rules every change follows.
- `Documentation/RepositoryGuardrails.md`: what the checks enforce.

## Never by default

- `Generated` folders and files marked `<auto-generated/>`: change the contract and regenerate.
- `Crest.xcodeproj`: edit `project.yml` and run `xcodegen generate`.
- `CrestShared/Resources/` asset catalogs, unless the change is an asset.
- The other platform's tree (CrestMobile for a Mac change, and the reverse) unless shared behavior moves.
