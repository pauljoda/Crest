# Organization, naming, and cohesive ownership plan

Reviewed revision: `457ac1d2`.

Crest’s naming should assume the browser context. Remove the blanket `Browser` prefix from feature directories and filenames, then migrate Swift symbols in separate, reviewable steps. Preserve meaningful role names and platform/framework seams. Consolidate code around cohesive owners and put reusable behavior in the appropriate shared feature and layer.

## Decision

Adopt feature directories such as `Extensions`, `Downloads`, `Navigation`, and `Favicons`. Use descriptive filenames such as `ExtensionControllerPool.swift`, `FaviconFallbackLoader.swift`, and `SessionStore.swift`. Keep `WebKit`, `UserDefaults`, `System`, and `Platform` when they identify an actual implementation or system seam. `BrowserDefaultBrowserController` should become `DefaultBrowserController`: the second “Browser” is the actual default-browser capability, not a redundant prefix.

Stage folders/files separately from Swift symbols. A filesystem move can preserve every declaration and wire contract. A symbol rename changes all call sites and may intersect imported APIs. Do not replace every occurrence of the string `Browser`: that would also change user copy, import-format keys, diagnostics, persisted keys, and browser-extension JavaScript APIs.

## Inventory and collision preflight

| Measurement at the audited revision | Result |
| --- | ---: |
| Shared Infrastructure Swift sources | 266 files / 23,402 raw lines |
| Immediate Infrastructure feature directories | 30; 22 begin with `Browser` |
| Swift files directly at Infrastructure root | 52 |
| Infrastructure folders containing Swift, including root/nested folders | 57 |
| Infrastructure files of 20 lines or fewer | 100 |
| Infrastructure files of 40 lines or fewer | 160 |
| Shared/Mac/Mobile filenames beginning with `Browser` | 1,256 / 556 / 63 |
| All production filenames beginning with `Browser` | 1,875 of 2,287 |
| Textually inventoried top-level declarations beginning with `Browser` | 2,308 of 2,715 |
| Duplicate Swift basenames inside Shared+Mac target | 0 |
| Duplicate Swift basenames inside Shared+Mobile target | 0 |
| Same Swift basenames reused across separate Mac/Mobile roots | 56, including 43 `BrowserPlatform*` pairs |

The tiny-file counts are evidence of navigation overhead, not a target to eliminate. Actual system ports, meaningful reusable models, and independently owned policies can deserve small files. Conversely, three private bookkeeping values used by one actor do not need three source files.

**File/path result:** a textual preflight that removes only a leading `Browser` from each path component found no new path or per-app Swift-basename collisions. A second, intentionally overbroad trial removing `Browser` anywhere in each component also found no local collisions, but that is not a valid naming policy: it would erase meaningful words such as `DefaultBrowser`. Existing same-name platform pairs must stay mutually exclusive by target membership.

**Swift symbol result:** the same leading-prefix preflight found no new collisions among the inventoried local top-level declarations in Shared+Mac or Shared+Mobile. This is not Swift name resolution: nested names, conditional declarations, imports, overloads, synthesized names, and generated code still need compilation.

**Verified imported-name collisions:** the installed Xcode 27 SwiftUI interface declares `Commands` and `Tab`. Therefore:

- `BrowserCommands` → `Commands` would collide with the protocol it conforms to (`struct Commands: Commands`). Use `AppCommands`, with explicit `SwiftUI.Commands` conformance if helpful.
- `BrowserTab` → `Tab` would shadow `SwiftUI.Tab`. The current model is a persisted Codable tab value ([Domain/BrowserTab/BrowserTab.swift:3](../../../CrestShared/Domain/BrowserTab/BrowserTab.swift#L3)). Prefer the natural domain name `Tab` and qualify framework tab declarations as `SwiftUI.Tab` where used. `TabRecord` is a viable alternative only if the team intentionally wants to emphasize its stored-record role. Do not recreate a blanket prefix as `Browsing*`.
- `BrowserStore` → `SessionStore` communicates its current ownership more precisely than bare `Store`. `BrowserPagePool` → `PagePool` and `MobileBrowserPageStore` → `MobilePageStore` can remain explicit adapters while their common lifecycle owners are extracted.

Inspection of the installed Xcode 27 SwiftUI interface confirmed both declarations. Exposed Foundation, WebKit, AppKit, and Observation Swift interfaces were also checked for exact matches from this textual inventory; that limited check found no additional matches. Both platform builds remain the authoritative validation for symbol changes.

## Concrete target map for Shared Infrastructure

Retain `CrestShared`, `CrestMac`, and `CrestMobile` as target roots. The requested cleanup is about redundant naming and ownership inside those roots; changing app target/module identity adds unrelated work. Proposed paths below use unprefixed filenames, with symbols migrated separately.

| Current sources | Target owner/location | Cohesion rule |
| --- | --- | --- |
| [BrowserExtensions](../../../CrestShared/Infrastructure/BrowserExtensions) (47 files), [BrowserExtensionServices](../../../CrestShared/Infrastructure/BrowserExtensionServices) (6), [WebKit/BrowserExtensions](../../../CrestShared/Infrastructure/WebKit/BrowserExtensions) (18) | `Infrastructure/Extensions/{Runtime,Installation,Compatibility,Services}` | Runtime/installation/compatibility are actual lifecycles. Move WebKit extension bridges with the extension feature, retaining their framework role in type names. Keep service-specific real capabilities together; no blanket Models/Services/Support scaffold. |
| [BrowserChromeWebStore](../../../CrestShared/Infrastructure/BrowserChromeWebStore) (15), [BrowserMozillaAddons](../../../CrestShared/Infrastructure/BrowserMozillaAddons) (11), loose source metadata files | `Infrastructure/Extensions/Sources/{ChromeWebStore,MozillaAddons}`; portable metadata in `Domain/Extensions` | HTTP acquisition, verification, unpacking stay Infrastructure. SwiftUI review presentation stays Features. Safari discovery/loading remains Mac Infrastructure; shared Safari source metadata can be neutral. |
| Loose in-memory/UserDefaults extension registry persistence | `Infrastructure/Extensions/Registry` | Registry storage and its disposable implementation are discoverable together; do not duplicate service policy here. |
| [CloudSync](../../../CrestShared/Infrastructure/CloudSync) plus loose `BrowserCloudRecord*`, journal persistence files | [Infrastructure/CloudSync](../../../CrestShared/Infrastructure/CloudSync) | CloudKit transport, record codecs, system fields, and journal persistence stay together. `BrowserSyncCoordinator` and its status belong in `Application/Sync` if retained as framework-neutral workflow coordination; avoid an Application → Infrastructure dependency solely because of current folder placement. |
| [Downloads](../../../CrestShared/Infrastructure/Downloads), [BrowserDownloadTransfer](../../../CrestShared/Infrastructure/BrowserDownloadTransfer), loose `BrowserDownloadDestination` | [Infrastructure/Downloads](../../../CrestShared/Infrastructure/Downloads) | Keep staging, transfer completion/quarantine, native download lifecycle, and destination resolution under Downloads. Related transfer-only values may share `DownloadTransfer.swift`. |
| [BrowserFaviconPalette](../../../CrestShared/Infrastructure/BrowserFaviconPalette) plus 10 loose favicon files | `Infrastructure/Favicons` | Capture/discovery, fallback loading, persistence, and palette acquisition are one capability; keep private fallback bookkeeping in its actor file. There are 13 files/965 lines across these current locations. |
| [BrowserAuthentication](../../../CrestShared/Infrastructure/BrowserAuthentication), [BrowserPasskeyAccess](../../../CrestShared/Infrastructure/BrowserPasskeyAccess), [BrowserSpaceAccess/SystemBrowserDeviceAuthenticator](../../../CrestShared/Infrastructure/BrowserSpaceAccess/SystemBrowserDeviceAuthenticator.swift) | `Infrastructure/Authentication` | Foundation-only permission/authentication values stay Domain; actual URL challenge, device-owner, and AuthenticationServices adapters live here with meaningful framework distinctions. |
| [Credentials](../../../CrestShared/Infrastructure/Credentials) plus loose credential bridge/proxy/secret lease/sensitive access/CSV export files | [Infrastructure/Credentials](../../../CrestShared/Infrastructure/Credentials) | Keychain, page credential messages, and file export are system-facing parts of credential behavior. Pure matching/capture/import values belong to shared Domain/Application, not beside WebKit merely for convenience. |
| [BrowserPageActions](../../../CrestShared/Infrastructure/BrowserPageActions), [BrowserReaderMode](../../../CrestShared/Infrastructure/BrowserReaderMode), [BrowserTabLifecycle](../../../CrestShared/Infrastructure/BrowserTabLifecycle), loose tab-state archive files | `Infrastructure/Pages` with `Actions`, `ReaderMode`, and `State` where those distinct lifecycles help | Shared runtime operations and archive I/O belong here. Keep the tab-state envelope/codec and restore policy next to the archive lifecycle owner initially; if their neutral contract is used by Application, move that contract inward without copying it. |
| Loose page configuration, website data store/removal/deferred cleanup, site-data policy, visited-link styler | [Infrastructure/WebKit](../../../CrestShared/Infrastructure/WebKit) with `WebsiteData` where useful | Actual engine configuration/storage stays explicit. Profile-owned website data is a different lifecycle from an individual page. Do not bury Space cleanup under a view feature. |
| [WebKit/Navigation](../../../CrestShared/Infrastructure/WebKit/Navigation), loose popup coordinator/scheme routing/tab host/registration/split/link hosts, [BrowserBlockedPopups](../../../CrestShared/Infrastructure/BrowserBlockedPopups) | Framework adapters in `Infrastructure/Navigation`; neutral host actions/results in `Application/Navigation`; pure routing decisions in `Domain/Navigation` | Move neutral contracts inward; keep WebKit delegates/content messages at the edge. Host actions can share a cohesive file with their small registration result. |
| [BrowserLinkPreferences](../../../CrestShared/Infrastructure/BrowserLinkPreferences) | `Infrastructure/Navigation/Preferences` | Preference storage supports shared navigation behavior. Its store remains Application and its values/policy Domain. |
| [BrowserFilterLists/ContentBlocking](../../../CrestShared/Infrastructure/BrowserFilterLists/ContentBlocking) | `Infrastructure/ContentBlocking` | The current parent adds a redundant layer above the six rule-list compiler/provider files. Keep compile/cache/provider lifecycle together. |
| [BrowserGeolocation](../../../CrestShared/Infrastructure/BrowserGeolocation) | `Infrastructure/Geolocation` | CoreLocation service, content bridge, and proxy keep a real system seam. Pure origin policy remains Domain. |
| [BrowserHostedWebNotifications](../../../CrestShared/Infrastructure/BrowserHostedWebNotifications) | `Infrastructure/Notifications` | Keep native delivery behind its shared request/permission contract. Do not merge extension notification policy and web-origin permission policy just because both display notifications. |
| [BrowserManualSetup](../../../CrestShared/Infrastructure/BrowserManualSetup), loose onboarding persistence | `Infrastructure/Onboarding` | Draft and progress persistence live together; their different schemas/keys remain explicit. |
| [BrowserStore/BrowserStore+Composition](../../../CrestShared/Infrastructure/BrowserStore/BrowserStore+Composition.swift), [BrowserLaunch/BrowserLaunchEnvironment+Process](../../../CrestShared/Infrastructure/BrowserLaunch/BrowserLaunchEnvironment+Process.swift), loose onboarding composition | `Infrastructure/Composition` | Production wiring and process reads stay at the outside edge. Domain/Application receive typed launch values and injected collaborators. |
| [BrowserSessionPersistence](../../../CrestShared/Infrastructure/BrowserSessionPersistence) | `Infrastructure/SessionPersistence` | The persisted-session implementation and status are discoverable together. Keep save scope/schema contracts inward when consumed by Application. |
| [BrowserWindowStatePersistence](../../../CrestShared/Infrastructure/BrowserWindowStatePersistence) | `Infrastructure/WindowState` | Window restoration is independently owned from portable session sync. |
| [BrowserShortcuts](../../../CrestShared/Infrastructure/BrowserShortcuts) | `Infrastructure/Shortcuts` | Defaults-backed bindings persist here; command IDs/conflicts/default policies stay inward. |
| [BrowserSitePermissions](../../../CrestShared/Infrastructure/BrowserSitePermissions) | `Infrastructure/SitePermissions` | Permission storage/production wiring here; authorization decisions and observable workflow retain their shared inward owners. |
| [MediaSessions](../../../CrestShared/Infrastructure/MediaSessions), [UserActivity](../../../CrestShared/Infrastructure/UserActivity) | Keep names and locations | Already descriptive; do not churn well-named capability folders merely for uniformity. |

The extension group currently spans five primary subtrees totaling 97 Swift files, plus five loose source/registry files: **102 files/12,919 raw lines**. This is conceptual scattering, not 102 duplicated implementations. There are no duplicate basenames inside shared Infrastructure; consolidation fixes discovery and ownership, not a filename conflict.

Within `Extensions`, keep filenames meaningful in search and diagnostics: `ExtensionControllerPool.swift` is preferable to `Pool.swift`, even inside an Extensions folder. The redundant product prefix can disappear without removing useful feature context.

## Specific ownership and file-cohesion changes

### Put private helpers with their only owner

[BrowserFaviconFallbackRequestToken.swift](../../../CrestShared/Infrastructure/BrowserFaviconFallbackRequestToken.swift) (4 lines), [BrowserFaviconFallbackRequestLease.swift](../../../CrestShared/Infrastructure/BrowserFaviconFallbackRequestLease.swift) (6), and [BrowserFaviconFallbackCacheKey.swift](../../../CrestShared/Infrastructure/BrowserFaviconFallbackCacheKey.swift) (6) are only referenced by [BrowserFaviconFallbackLoader.swift](../../../CrestShared/Infrastructure/BrowserFaviconFallbackLoader.swift) and one another across production; no direct test references were found. Place them as private nested `RequestToken`, `RequestLease`, and `CacheKey` values in `Infrastructure/Favicons/FaviconFallbackLoader.swift`. Preserve the actor’s download/cache/generation lifecycle as one cohesive owner rather than splitting methods out. Existing behavior tests should continue to exercise its public behavior.

Likewise `BrowserCloudRecordCodecError` is used only by `BrowserCloudRecordCodec` in production. Co-locate it with `CloudRecordCodec.swift` (nested or file-scoped according to external test/API use); it does not need a separate Error folder or protocol. `BrowserSyncCoordinatorStatus`, by contrast, is exposed through the application store, so it belongs with the shared Application coordinator contract rather than becoming a private implementation detail.

### Move reused neutral contracts inward, not into a generic shared bucket

- [Infrastructure/BrowserPopupTabHost.swift:7](../../../CrestShared/Infrastructure/BrowserPopupTabHost.swift#L7) is an actions value used by both page-runtime adapters and [Application/BrowserStore/BrowserStore+TabLifecycle.swift:156](../../../CrestShared/Application/BrowserStore/BrowserStore+TabLifecycle.swift#L156). Its companion [BrowserPopupTabRegistration.swift:6](../../../CrestShared/Infrastructure/BrowserPopupTabRegistration.swift#L6) contains only a tab and a Space. Remove the unused WebKit imports and place both in one `Application/Navigation/PopupTabHost.swift`. This removes a real inward dependency without adding a protocol.
- [Infrastructure/BrowserPopupDisposition.swift:1](../../../CrestShared/Infrastructure/BrowserPopupDisposition.swift#L1) actually declares `BrowserAutomaticPopupPolicy`, not a disposition. Rename according to its real role and place its pure permission decision in `Domain/Navigation/PopupPolicy.swift`. Its related `BrowserPopupSchemeRouting` classifies a URL using a Domain scheme policy and needs no WebKit type; the tightly related URL/popup policy can share this file if that makes the policy easier to read.
- [Features/DataPortability/Models/BrowserPortableArchive](../../../CrestShared/Features/DataPortability/Models/BrowserPortableArchive.swift) and `BrowserImportSpaceCustomization` are used by manual setup Domain/Application. Move their portable schema/customization values to `Domain/DataPortability`; move review workflow to `Application/DataPortability`; leave UI in [Features/DataPortability](../../../CrestShared/Features/DataPortability) and actual file readers/writers in Infrastructure. This is shared relevant ownership, not merely moving code between visual folders.
- [BrowserStore.swift:19](../../../CrestShared/Application/BrowserStore/BrowserStore.swift#L19) currently owns Features sidebar drag/reorder state, including pointer geometry and landing previews. Move that presentation state to the shared Sidebar feature owner. Application tab operations accept neutral runtime assignments and return mutation results; the sidebar reconciles its drag from that result. Reused UI state is shared presentation, not automatically Domain.

If two Mac features share an AppKit implementation, place it in the appropriate common **Mac** capability owner. Cross-feature reuse alone is not grounds to move platform-specific code into `CrestShared`. Shared neutral behavior and shared SwiftUI presentation belong in their corresponding shared layer; actual adapters remain target-specific.

## Named large-owner decomposition, with real boundaries

These are implementation directions for cohesive units, not requests to split every method or impose a line limit.

**PagePool / MobilePageStore — three shared ownership boundaries plus their platform adapters.** Current platform owners are 2,591/1,757 lines, and their repeated archive restoration/reconciliation is documented in the [core and capability audit](core-and-capabilities.md#c1--high-priority-common-page-runtime-lifecycle-orchestration-still-has-two-production-owners).

1. `TabStateLifecycle`: pending-copy state, archive restore/prune bookkeeping, generation/profile checks. Both pools invoke it; actual WebKit state capture remains a supplied operation. Keep envelope-related helpers with this owner where cohesive.
2. `PageReconciliation`: compute valid assignments, archive-before-release decisions, and presented/resident reconciliation. The platform adapter executes releases and maintains any desktop suspended-card distinction.
3. `ContentBlockingCoordinator`: compare Space policy revisions and decide immediate versus next-navigation activation for presented/background/transient pages. Platform adapters supply page collections, including suspended desktop pages.

Keep AppKit/UIKit page creation, view attachment, native dialogs, and platform presentation in their existing explicit adapters. Do not create a new universal page superclass or move all methods into same-owner extension files: those approaches preserve the original concentration of responsibility.

**DownloadCenter — three runtime ownership boundaries.** [Infrastructure/Downloads/BrowserDownloadCenter.swift](../../../CrestShared/Infrastructure/Downloads/BrowserDownloadCenter.swift) is 937 lines. At `:56`–`:78`, many parallel dictionaries carry the same download identity through registration, progress, staging, destination, retry, and authentication.

1. `DownloadSession` groups one live WKDownload’s registration/progress/path/security-scope state so cleanup is one lifecycle, replacing synchronization across numerous dictionaries. It is a cohesive internal value/owner in the same download runtime file initially, not one file per field.
2. `DownloadApprovalCoordinator` owns automatic-download sequence/retry approval and risk/destination decision flow (`destinationURL` at `:573`, approval at `:832`). Reuse existing Domain download/permission policies; keep native destination UI behind current injected actions.
3. `DownloadCenter` remains the observable ledger and high-level start/cancel/retry/finish facade; its feedback-expiry state may stay here unless independently reused. Move a separate feedback owner only when its lifecycle warrants it, not to hit a size target.

Validate cancellation, retry registration, Space deletion, authentication, quarantine rollback, security-scoped resource release, and finished/unacknowledged ledger behavior. Preserve existing user-visible semantics.

**SidebarWidgetHost — four cohesive files, not dozens of leaf views.** The current 1,675-line file already contains several distinct types rather than a single monolithic type.

1. `SidebarWidgetDeck.swift`: host (`:202`), deck (`:327`), stepper (`:539`), selection, geometry, and deck-local values.
2. `NowPlayingWidget.swift`: media card (`:836`), artwork, transport/volume controls, and their private helpers.
3. `SoftwareUpdateWidget.swift`: update card (`:1145`), icon, progress/status/actions, and private update-only helpers.
4. `SidebarWidgetChrome.swift`: only modifiers/styles actually reused by the two card kinds (`:776`, `:791`, control styles at `:1435` onward). Deck-only metrics remain with the deck; helper names alone are not a reason to put them in a global chrome file.

This lets an update-card change be reviewed without traversing playback controls, while the meaningful subviews and their small values remain together. Keep shared canonical UI and feed platform-specific capabilities/actions from the shell.

## Rename-sensitive contracts that must remain stable

| Evidence | Required treatment |
| --- | --- |
| [Infrastructure/BrowserManualSetup/BrowserManualSetupDraftStore.swift:4](../../../CrestShared/Infrastructure/BrowserManualSetup/BrowserManualSetupDraftStore.swift#L4), key `BrowserManualSetupDraft` | Keep the stored key even if owner/file becomes `ManualSetupDraftStore`. A key change is a separate migration, not a naming cleanup. |
| [Infrastructure/UserDefaultsBrowserSyncJournalPersistence.swift:12](../../../CrestShared/Infrastructure/UserDefaultsBrowserSyncJournalPersistence.swift#L12), default `crest.sync.journal.v1` | Preserve storage namespaces/schema selection. Likewise preserve existing onboarding/session/shortcut preference keys. |
| [Infrastructure/BrowserCloudRecordCodec.swift:153](../../../CrestShared/Infrastructure/BrowserCloudRecordCodec.swift#L153), types `CrestSpace`, `CrestFolder`, `CrestTab`, `CrestHistory`, `CrestArchive` | Preserve CloudKit record names, field keys, zone names, and sync IDs. Swift type/file names do not authorize changing the backend schema. |
| [Infrastructure/BrowserCloudRecordSystemFields.swift:23](../../../CrestShared/Infrastructure/BrowserCloudRecordSystemFields.swift#L23) and `:39`, secure coding of CKRecord system fields | Preserve Apple's archived class contract. The inspected archive holds CKRecord system fields, not a detected custom Browser-prefixed NSCoding class; do not invent a class-name migration without evidence. |
| [Infrastructure/BrowserTabStateEnvelope.swift:16](../../../CrestShared/Infrastructure/BrowserTabStateEnvelope.swift#L16), `CRTS` magic/version; [BrowserTabStateArchive.swift:60](../../../CrestShared/Infrastructure/BrowserTabStateArchive.swift#L60) | Preserve tab archive framing, URL/profile/tab identity, directory layout, and compatibility checks. |
| [Infrastructure/BrowserCredentialContentBridge.swift:6](../../../CrestShared/Infrastructure/BrowserCredentialContentBridge.swift#L6)/`:73`, `crestCredentials` and JS handler use | Keep JS handler names, content worlds, bridge messages, and externally visible extension APIs byte-for-byte unless intentionally changing the protocol. Never replace `browser.*` WebExtension APIs. |
| [Infrastructure/BrowserExtensions/Controller/BrowserExtensionPersistenceController.swift:121](../../../CrestShared/Infrastructure/BrowserExtensions/Controller/BrowserExtensionPersistenceController.swift#L121), notification `BrowserExtensionDiagnosticsLogDidRecord` | Preserve the notification string through a Swift symbol rename; update internal symbol references, not the transport name. |
| [CrestMac/Infrastructure/WebKit/BrowserExtensionWebpageMenuProvider.swift:177](../../../CrestMac/Infrastructure/WebKit/BrowserExtensionWebpageMenuProvider.swift#L177), `@objc(performExtensionWebpageMenuItem:)` | Keep explicit Objective-C selector spelling and #selector/delegate wiring. Runtime class lookup/selector literals in WebKit bridges identify Apple APIs, not Crest naming debt. |
| [project.yml:49](../../../project.yml#L49)/`:105`, target source roots; architecture/preview checks and documentation | Regenerate XcodeGen outputs after moves; update exact path/symbol references in supported guards, exception ledgers, previews, scripts and docs. Preserve target-exclusive `Platform*` pairs. |

Keep Codable property/case raw values, portable archive schema, source import-format keys, URL schemes, UTIs, Keychain service/access-group strings, bundle identifiers, accessibility IDs, and localization keys stable. Ordinary Codable type renames do not by themselves rename JSON fields; changing properties or enum cases may. Audit those changes explicitly rather than treating all text matches alike.

## Ordered implementation and validation

1. Record the exact implementation baseline and existing failing checks, using the [audit validation record](validation.md) as the starting evidence. Generate a reviewed old→new path map and a separate old→new symbol map; register the two known SwiftUI collisions and intentional target-specific same-name pairs. Restrict each step to a meaningful feature slice.
2. Move/rename the infrastructure feature paths with declarations unchanged. Consolidate loose files into their actual owner; shorten redundant `Browser` filenames. Update project generation inputs/guard path references together and regenerate XcodeGen output. Confirm both target memberships and unchanged resource inclusion.
3. Perform symbol renames per feature with Swift-aware references where possible. Choose `AppCommands`, preserve semantic `DefaultBrowser`, and explicitly qualify `SwiftUI.Tab` if the model becomes `Tab`. Review all string-literal diffs; keep externally stored or messaged identifiers unchanged.
4. Separately co-locate proven private helpers and move shared neutral contracts inward. Do not mix those ownership changes with lifecycle extraction until the mechanical rename builds cleanly; that preserves a reviewable cause for any failure.
5. Extract the three page-runtime owners, download lifecycle ownership, and widget groups in independent changes using existing behavior and platform integration coverage. Do not add tests asserting filenames, source topology, declaration counts, or unchanged implementation trivia.
6. Per step run supported architecture/vertical/public-source checks and changed-file formatting, compile both affected app targets, and run the smallest relevant behavior suites. Before the consolidated rename lands, build macOS+iOS Debug and Release and run persistence/import/sync migration coverage plus command/menu/preview/native-adapter smoke validation in isolated sessions. Compare failure output to the recorded baseline; do not hide unrelated stale tests or silently claim the suite is clean.

The destination is less naming noise, fewer ownership hops, and a shared implementation for reused behavior. It should also contain fewer helper-only files where a single cohesive owner is clearer; no numeric file-count or file-length goal is required.

## Acceptance criteria

The organization work is ready to land when:

- Feature directories and source filenames use the agreed naming map; any retained `Browser` word describes an actual capability, protocol, or external contract.
- Both app targets compile with the renamed symbols, including explicit handling of `SwiftUI.Commands` and `SwiftUI.Tab`; platform adapter pairs remain correctly excluded from the opposite target.
- Shared reused policy and values have one owner in their relevant Domain/Application feature, shared UI has one canonical presentation owner, and AppKit/UIKit implementations remain in the platform roots.
- Private helper values live with their sole owner. Larger files are separated only at the named lifecycle, reusable component, or system boundaries; the work does not create one file per helper.
- The existing storage keys, CloudKit identifiers, Codable fields, archive framing, Keychain namespaces, Objective-C selectors, JavaScript messages, URL schemes, and bundle identifiers remain compatible with the reviewed baseline.
- The selected lifecycle/command/permission/persistence tests and isolated platform checks demonstrate unchanged user workflows. Any pre-existing test failure is explicitly distinguished from a new failure.
- Supported repository guards and changed-file formatting pass, with any accepted existing debt still documented accurately; generated Xcode project membership and documentation match the new source map.
- Reviewers can trace each shared owner to its callers and validate each behavioral extraction independently of the mechanical renames.
