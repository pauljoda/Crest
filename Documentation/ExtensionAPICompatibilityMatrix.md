# Crest WebExtension API compatibility matrix

This document records the browser contract Crest exposes to portable Chrome and
Firefox WebExtensions. The executable source of truth is
`BrowserExtensionAPICompatibilityMatrix`; package preparation, capability
broker authorization, and WebKit API hiding must derive from that matrix rather
than from extension identities, source scans, or opportunistic
`existing === undefined` checks.

The tables below are generated from that Swift matrix by
`BrowserExtensionAPICompatibilityMatrix.generatedDocumentationMarkdown()`.
`BrowserExtensionAPICompatibilityMatrixDocumentationTests` fails when the block
and the matrix disagree, so a routing change lands in both places or not at
all. Regenerate with:

```sh
TEST_RUNNER_CREST_WRITE_EXTENSION_MATRIX_DOCS=1 \
  xcodebuild test -only-testing:CrestTests/BrowserExtensionAPICompatibilityMatrixDocumentationTests …
```

Everything outside the generated block is hand written, because it states
intent and boundaries that no array can express.

## Pinned specification inputs

- Chromium extension schemas and feature gates:
  [`209681af9aaea48aa172a1a9eb1eb2cdc63c1e67`](https://chromium.googlesource.com/chromium/src/+/209681af9aaea48aa172a1a9eb1eb2cdc63c1e67/chrome/common/extensions/api/)
  and [common schemas](https://chromium.googlesource.com/chromium/src/+/209681af9aaea48aa172a1a9eb1eb2cdc63c1e67/extensions/common/api/).
- Firefox WebExtension schemas:
  [`5836a062726f715fda621338a17b51aff30d0a8c`](https://github.com/mozilla/gecko-dev/tree/5836a062726f715fda621338a17b51aff30d0a8c/toolkit/components/extensions/schemas).
- WebKit extension IDL/runtime:
  [`e4856c6696f58bae6f5cf1e864d0550f9eff09f8`](https://github.com/WebKit/WebKit/tree/e4856c6696f58bae6f5cf1e864d0550f9eff09f8/Source/WebKit/WebProcess/Extensions/API).
- Shipping interface used by this pass: Xcode 27.0 (27A5252f), macOS 27.0
  SDK. The installed `WKWebExtensionContext.h` is authoritative for the host
  API Crest can call.

These revisions are the ones pinned in the matrix, and the documentation test
rejects any other revision hash appearing in this file. Updating a source
revision is a deliberate compatibility review, not a background behavior
change.

## Generated routing tables

<!-- BEGIN GENERATED: BrowserExtensionAPICompatibilityMatrix -->
### Pinned revisions

| Source | Pinned revision |
| --- | --- |
| Chromium schemas | `209681af9aaea48aa172a1a9eb1eb2cdc63c1e67` |
| Firefox schemas | `5836a062726f715fda621338a17b51aff30d0a8c` |
| WebKit extension IDL | `e4856c6696f58bae6f5cf1e864d0550f9eff09f8` |
| Apple SDK | Xcode 27.0 (27A5252f), macOS 27.0 SDK |

### Namespace routes

Routes are **Native** (WebKit unchanged), **Native + patch** (WebKit identity kept, one contract gap filled), **Emulated** (Crest owns the implementation), and **Unavailable** (no false success). Processes are **BG** (background worker or page), **EP** (extension page or popup), **CS** (content script), and **DT** (DevTools page). Permissions lists the manifest permissions the matrix associates with the namespace; Exposure is the narrower question the compatibility runtime actually asks before it publishes `browser.<namespace>` at all, and the two differ where Chrome defines a namespace regardless of the manifest. Broker lists the permissions the Crest capability broker will authorize for that namespace.

| Namespace | Chrome | Firefox | WebKit | Crest route | Processes | Permissions | Exposure | Broker |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `action` | Native | Native | Native | Native + patch | BG, EP | — | Always | — |
| `alarms` | Native | Native | Native | Native + patch | BG, EP | — | Always | — |
| `bookmarks` | Native | Native | Unavailable | Unavailable | BG, EP | `bookmarks` | `bookmarks` | — |
| `browserAction` | Native | Native | Native | Native + patch | BG, EP | — | Always | — |
| `commands` | Native | Native | Native | Native + patch | BG, EP | — | Always | — |
| `contextMenus` | Native | Native | Native | Native + patch | BG, EP | `contextMenus`, `menus` | `contextMenus`, `menus` | `contextMenus`, `menus` |
| `cookies` | Native | Native | Native | Native | BG, EP | `cookies` | `cookies` | — |
| `debugger` | Native | Native | Unavailable | Emulated | BG, EP | `debugger` | `debugger` | `debugger` |
| `declarativeNetRequest` | Native | Native | Partial | Native + patch | BG, EP | `declarativeNetRequest`, `declarativeNetRequestFeedback`, `declarativeNetRequestWithHostAccess` | `declarativeNetRequest`, `declarativeNetRequestFeedback`, `declarativeNetRequestWithHostAccess` | `declarativeNetRequest`, `declarativeNetRequestWithHostAccess` |
| `devtools` | Native | Native | Partial | Native | DT | — | Always | — |
| `dom` | Native | Unavailable | Native | Native | EP, CS | — | Always | — |
| `downloads` | Native | Native | Unavailable | Emulated | BG, EP | `downloads`, `downloads.open` | `downloads`, `downloads.open` | `downloads` |
| `extension` | Native | Native | Native | Native + patch | BG, EP, CS | — | Always | — |
| `history` | Native | Native | Unavailable | Unavailable | BG, EP | `history` | `history` | — |
| `i18n` | Native | Native | Native | Native + patch | BG, EP, CS | — | Always | — |
| `identity` | Native | Partial | Unavailable | Emulated | BG, EP | `identity`, `identity.email` | `identity`, `identity.email` | `identity` |
| `idle` | Native | Native | Unavailable | Emulated | BG, EP | `idle` | `idle` | `idle` |
| `management` | Native | Native | Unavailable | Emulated | BG, EP | `management` | `management` | — |
| `notifications` | Native | Native | Partial | Emulated | BG, EP | `notifications` | `notifications` | `notifications` |
| `offscreen` | Native | Unavailable | Partial | Emulated | BG, EP | `offscreen` | `offscreen` | `offscreen` |
| `omnibox` | Native | Native | Unavailable | Unavailable | BG, EP | `omnibox` | `omnibox` | — |
| `pageAction` | Native | Native | Native | Native | BG, EP | — | Always | — |
| `permissions` | Native | Native | Native | Native + patch | BG, EP | `permissions` | Always | — |
| `privacy` | Native | Native | Unavailable | Emulated | BG, EP | `privacy` | `privacy` | — |
| `runtime` | Native | Native | Native | Native + patch | BG, EP, CS | — | Always | — |
| `scripting` | Native | Native | Native | Native + patch | BG, EP | `scripting` | `scripting` | — |
| `sessions` | Native | Native | Unavailable | Unavailable | BG, EP | `sessions` | `sessions` | — |
| `sidePanel` | Native | Unavailable | Partial | Emulated | BG, EP | `sidePanel` | `sidePanel` | `sidePanel` |
| `sidebarAction` | Unavailable | Native | Partial | Emulated | BG, EP | — | Manifest `sidebar_action` | — |
| `storage` | Native | Native | Native | Native + patch | BG, EP, CS | `storage`, `unlimitedStorage` | `storage`, `unlimitedStorage` | — |
| `tabGroups` | Native | Native | Unavailable | Emulated | BG, EP | `tabGroups` | `tabGroups` | `tabGroups` |
| `tabs` | Native | Native | Native | Native + patch | BG, EP | `tabs` | Always | — |
| `test` | Unavailable | Unavailable | Native | Unavailable | BG, EP, CS | — | Always | — |
| `topSites` | Native | Native | Unavailable | Unavailable | BG, EP | `topSites` | `topSites` | — |
| `userScripts` | Native | Native | Unavailable | Unavailable | BG, EP | `userScripts` | `userScripts` | — |
| `webNavigation` | Native | Native | Native | Native + patch | BG, EP | `webNavigation` | `webNavigation` | — |
| `webRequest` | Native | Native | Partial | Native + patch | BG, EP | `webRequest`, `webRequestBlocking` | `webRequest`, `webRequestBlocking` | — |
| `windows` | Native | Native | Native | Native + patch | BG, EP | — | Always | — |

### Member routes

A namespace can stay native while a single dynamic member is replaced. **Hidden from WebKit** marks the members Crest removes from the native surface before the extension context loads.

| Member | WebKit | Crest route | Processes | Hidden from WebKit |
| --- | --- | --- | --- | --- |
| `action.getUserSettings` | Native | Native + patch | BG, EP | — |
| `action.onUserSettingsChanged` | Unavailable | Presence only | BG, EP | — |
| `action.setBadgeTextColor` | Unavailable | Emulated | BG, EP | — |
| `alarms.onAlarm` | Native | Native + patch | BG, EP | — |
| `browserAction.getUserSettings` | Native | Native + patch | BG, EP | — |
| `browserAction.onUserSettingsChanged` | Unavailable | Presence only | BG, EP | — |
| `browserAction.setBadgeTextColor` | Unavailable | Emulated | BG, EP | — |
| `contextMenus.create` | Native | Native + patch | BG, EP | — |
| `contextMenus.onClicked` | Native | Native + patch | BG, EP | — |
| `contextMenus.remove` | Native | Native + patch | BG, EP | — |
| `contextMenus.removeAll` | Native | Native + patch | BG, EP | — |
| `contextMenus.update` | Native | Native + patch | BG, EP | — |
| `debugger.DetachReason` | Unavailable | Emulated | BG, EP | — |
| `debugger.TargetInfoType` | Unavailable | Emulated | BG, EP | — |
| `debugger.attach` | Unavailable | Emulated | BG, EP | — |
| `debugger.detach` | Unavailable | Emulated | BG, EP | — |
| `debugger.getTargets` | Unavailable | Emulated | BG, EP | — |
| `debugger.onDetach` | Unavailable | Emulated | BG, EP | — |
| `debugger.onEvent` | Unavailable | Emulated | BG, EP | — |
| `debugger.sendCommand` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.DYNAMIC_RULESET_ID` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.DomainType` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.GETMATCHEDRULES_QUOTA_INTERVAL` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.GUARANTEED_MINIMUM_STATIC_RULES` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.HeaderOperation` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.MAX_GETMATCHEDRULES_CALLS_PER_INTERVAL` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.MAX_NUMBER_OF_DYNAMIC_AND_SESSION_RULES` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.MAX_NUMBER_OF_DYNAMIC_RULES` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.MAX_NUMBER_OF_ENABLED_STATIC_RULESETS` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.MAX_NUMBER_OF_REGEX_RULES` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.MAX_NUMBER_OF_SESSION_RULES` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.MAX_NUMBER_OF_STATIC_RULESETS` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.MAX_NUMBER_OF_UNSAFE_DYNAMIC_RULES` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.MAX_NUMBER_OF_UNSAFE_SESSION_RULES` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.RequestMethod` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.ResourceType` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.RuleActionType` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.SESSION_RULESET_ID` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.UnsupportedRegexReason` | Unavailable | Emulated | BG, EP | — |
| `declarativeNetRequest.getDynamicRules` | Partial | Native + patch | BG, EP | — |
| `declarativeNetRequest.getSessionRules` | Partial | Native + patch | BG, EP | — |
| `declarativeNetRequest.updateDynamicRules` | Partial | Native + patch | BG, EP | — |
| `declarativeNetRequest.updateSessionRules` | Partial | Native + patch | BG, EP | — |
| `downloads.acceptDanger` | Unavailable | Presence only | BG, EP | — |
| `downloads.cancel` | Unavailable | Presence only | BG, EP | — |
| `downloads.download` | Unavailable | Emulated | BG, EP | — |
| `downloads.erase` | Unavailable | Presence only | BG, EP | — |
| `downloads.getFileIcon` | Unavailable | Presence only | BG, EP | — |
| `downloads.onChanged` | Unavailable | Presence only | BG, EP | — |
| `downloads.onCreated` | Unavailable | Presence only | BG, EP | — |
| `downloads.onDeterminingFilename` | Unavailable | Presence only | BG, EP | — |
| `downloads.onErased` | Unavailable | Presence only | BG, EP | — |
| `downloads.open` | Unavailable | Presence only | BG, EP | — |
| `downloads.pause` | Unavailable | Presence only | BG, EP | — |
| `downloads.removeFile` | Unavailable | Presence only | BG, EP | — |
| `downloads.resume` | Unavailable | Presence only | BG, EP | — |
| `downloads.search` | Unavailable | Presence only | BG, EP | — |
| `downloads.setShelfEnabled` | Unavailable | Presence only | BG, EP | — |
| `downloads.setUiOptions` | Unavailable | Presence only | BG, EP | — |
| `downloads.show` | Unavailable | Presence only | BG, EP | — |
| `downloads.showDefaultFolder` | Unavailable | Presence only | BG, EP | — |
| `extension.getBackgroundPage` | Native | Native + patch | BG, EP | — |
| `extension.getViews` | Native | Native + patch | BG, EP | — |
| `i18n.getMessage` | Native | Native + patch | BG, EP, CS | — |
| `identity.AccountStatus` | Unavailable | Emulated | BG, EP | — |
| `identity.clearAllCachedAuthTokens` | Unavailable | Emulated | BG, EP | — |
| `identity.getAccounts` | Unavailable | Emulated | BG, EP | — |
| `identity.getAuthToken` | Unavailable | Emulated | BG, EP | — |
| `identity.getProfileUserInfo` | Unavailable | Emulated | BG, EP | — |
| `identity.getRedirectURL` | Unavailable | Emulated | BG, EP | — |
| `identity.launchWebAuthFlow` | Unavailable | Emulated | BG, EP | — |
| `identity.onSignInChanged` | Unavailable | Emulated | BG, EP | — |
| `identity.removeCachedAuthToken` | Unavailable | Emulated | BG, EP | — |
| `idle.getAutoLockDelay` | Unavailable | Presence only | BG, EP | — |
| `idle.onStateChanged` | Unavailable | Emulated | BG, EP | — |
| `idle.queryState` | Unavailable | Emulated | BG, EP | — |
| `idle.setDetectionInterval` | Unavailable | Emulated | BG, EP | — |
| `management.createAppShortcut` | Unavailable | Presence only | BG, EP | — |
| `management.generateAppForLink` | Unavailable | Presence only | BG, EP | — |
| `management.get` | Unavailable | Presence only | BG, EP | — |
| `management.getAll` | Unavailable | Presence only | BG, EP | — |
| `management.getPermissionWarningsById` | Unavailable | Presence only | BG, EP | — |
| `management.getPermissionWarningsByManifest` | Unavailable | Presence only | BG, EP | — |
| `management.getSelf` | Unavailable | Emulated | BG, EP | — |
| `management.launchApp` | Unavailable | Presence only | BG, EP | — |
| `management.onDisabled` | Unavailable | Presence only | BG, EP | — |
| `management.onEnabled` | Unavailable | Presence only | BG, EP | — |
| `management.onInstalled` | Unavailable | Presence only | BG, EP | — |
| `management.onUninstalled` | Unavailable | Presence only | BG, EP | — |
| `management.setEnabled` | Unavailable | Presence only | BG, EP | — |
| `management.setLaunchType` | Unavailable | Presence only | BG, EP | — |
| `management.uninstall` | Unavailable | Presence only | BG, EP | — |
| `management.uninstallSelf` | Unavailable | Presence only | BG, EP | — |
| `notifications.clear` | Partial | Emulated | BG, EP | — |
| `notifications.create` | Partial | Emulated | BG, EP | — |
| `notifications.getAll` | Partial | Emulated | BG, EP | — |
| `notifications.getPermissionLevel` | Partial | Emulated | BG, EP | — |
| `notifications.onButtonClicked` | Partial | Emulated | BG, EP | — |
| `notifications.onClicked` | Partial | Emulated | BG, EP | — |
| `notifications.onClosed` | Partial | Emulated | BG, EP | — |
| `notifications.onPermissionLevelChanged` | Partial | Presence only | BG, EP | — |
| `notifications.onShowSettings` | Partial | Presence only | BG, EP | — |
| `notifications.update` | Partial | Emulated | BG, EP | — |
| `offscreen.Reason` | Partial | Emulated | BG, EP | — |
| `offscreen.closeDocument` | Partial | Emulated | BG, EP | — |
| `offscreen.createDocument` | Partial | Emulated | BG, EP | — |
| `offscreen.hasDocument` | Partial | Emulated | BG, EP | — |
| `permissions.contains` | Native | Native + patch | BG, EP | — |
| `permissions.getAll` | Native | Native + patch | BG, EP | — |
| `permissions.remove` | Native | Native + patch | BG, EP | — |
| `privacy.network` | Unavailable | Emulated | BG, EP | — |
| `privacy.services` | Unavailable | Emulated | BG, EP | — |
| `privacy.websites` | Unavailable | Emulated | BG, EP | — |
| `runtime.ContextType` | Unavailable | Emulated | BG, EP | — |
| `runtime.OnInstalledReason` | Unavailable | Emulated | BG, EP | — |
| `runtime.OnRestartRequiredReason` | Unavailable | Emulated | BG, EP | — |
| `runtime.PlatformArch` | Unavailable | Emulated | BG, EP | — |
| `runtime.PlatformNaclArch` | Unavailable | Emulated | BG, EP | — |
| `runtime.PlatformOs` | Unavailable | Emulated | BG, EP | — |
| `runtime.RequestUpdateCheckStatus` | Unavailable | Emulated | BG, EP | — |
| `runtime.getBackgroundPage` | Native | Native + patch | BG, EP | — |
| `runtime.getContexts` | Unavailable | Emulated | BG, EP | — |
| `runtime.getManifest` | Native | Native + patch | BG, EP, CS | — |
| `runtime.getURL` | Native | Native + patch | BG, EP, CS | — |
| `runtime.id` | Native | Native + patch | BG, EP, CS | — |
| `runtime.onConnect` | Native | Native + patch | BG, EP, CS | — |
| `runtime.onMessage` | Native | Native + patch | BG, EP, CS | — |
| `runtime.onUpdateAvailable` | Native | Native + patch | BG, EP | — |
| `runtime.requestUpdateCheck` | Native | Native + patch | BG, EP | — |
| `scripting.ExecutionWorld` | Native | Native + patch | BG, EP | — |
| `sidePanel.Side` | Partial | Emulated | BG, EP | — |
| `sidePanel.close` | Partial | Emulated | BG, EP | — |
| `sidePanel.getLayout` | Partial | Emulated | BG, EP | — |
| `sidePanel.getOptions` | Partial | Emulated | BG, EP | — |
| `sidePanel.getPanelBehavior` | Partial | Emulated | BG, EP | — |
| `sidePanel.onClosed` | Partial | Emulated | BG, EP | — |
| `sidePanel.onOpened` | Partial | Emulated | BG, EP | — |
| `sidePanel.open` | Partial | Emulated | BG, EP | — |
| `sidePanel.setOptions` | Partial | Emulated | BG, EP | — |
| `sidePanel.setPanelBehavior` | Partial | Emulated | BG, EP | — |
| `sidebarAction.close` | Partial | Emulated | BG, EP | — |
| `sidebarAction.getPanel` | Partial | Emulated | BG, EP | — |
| `sidebarAction.getTitle` | Partial | Emulated | BG, EP | — |
| `sidebarAction.isOpen` | Partial | Emulated | BG, EP | — |
| `sidebarAction.open` | Partial | Emulated | BG, EP | — |
| `sidebarAction.setIcon` | Partial | Emulated | BG, EP | — |
| `sidebarAction.setPanel` | Partial | Emulated | BG, EP | — |
| `sidebarAction.setTitle` | Partial | Emulated | BG, EP | — |
| `sidebarAction.toggle` | Partial | Emulated | BG, EP | — |
| `storage.local` | Native | Native + patch | BG, EP, CS | — |
| `storage.managed` | Native | Native + patch | BG, EP, CS | — |
| `storage.session` | Native | Native + patch | BG, EP, CS | — |
| `storage.sync` | Native | Native + patch | BG, EP, CS | — |
| `tabGroups.Color` | Unavailable | Emulated | BG, EP | — |
| `tabGroups.TAB_GROUP_ID_NONE` | Unavailable | Emulated | BG, EP | — |
| `tabGroups.get` | Unavailable | Emulated | BG, EP | — |
| `tabGroups.move` | Unavailable | Emulated | BG, EP | — |
| `tabGroups.onCreated` | Unavailable | Emulated | BG, EP | — |
| `tabGroups.onMoved` | Unavailable | Emulated | BG, EP | — |
| `tabGroups.onRemoved` | Unavailable | Emulated | BG, EP | — |
| `tabGroups.onUpdated` | Unavailable | Emulated | BG, EP | — |
| `tabGroups.query` | Unavailable | Emulated | BG, EP | — |
| `tabGroups.update` | Unavailable | Emulated | BG, EP | — |
| `tabs.get` | Native | Native + patch | BG, EP | — |
| `tabs.group` | Unavailable | Emulated | BG, EP | — |
| `tabs.move` | Unavailable | Emulated | BG, EP | — |
| `tabs.query` | Native | Native + patch | BG, EP | — |
| `tabs.sendMessage` | Native | Native + patch | BG, EP | — |
| `tabs.ungroup` | Unavailable | Emulated | BG, EP | — |
| `webNavigation.getAllFrames` | Native | Native + patch | BG, EP | — |
| `webNavigation.onCreatedNavigationTarget` | Unavailable | Presence only | BG, EP | — |
| `webNavigation.onHistoryStateUpdated` | Unavailable | Presence only | BG, EP | — |
| `webNavigation.onReferenceFragmentUpdated` | Unavailable | Presence only | BG, EP | — |
| `webNavigation.onTabReplaced` | Unavailable | Presence only | BG, EP | — |
| `webRequest.handlerBehaviorChanged` | Partial | Native + patch | BG, EP | — |
| `webRequest.onActionIgnored` | Unavailable | Native + patch | BG, EP | — |
| `webRequest.onAuthRequired` | Partial | Unavailable | BG, EP | Yes |
| `webRequest.onBeforeRedirect` | Native | Native + patch | BG, EP | — |
| `webRequest.onBeforeRequest` | Native | Native + patch | BG, EP | — |
| `webRequest.onBeforeSendHeaders` | Native | Native + patch | BG, EP | — |
| `webRequest.onCompleted` | Native | Native + patch | BG, EP | — |
| `webRequest.onErrorOccurred` | Native | Native + patch | BG, EP | — |
| `webRequest.onHeadersReceived` | Native | Native + patch | BG, EP | — |
| `webRequest.onResponseStarted` | Native | Native + patch | BG, EP | — |
| `webRequest.onSendHeaders` | Native | Native + patch | BG, EP | — |
| `windows.create` | Native | Native + patch | BG, EP | — |
| `windows.update` | Native | Native + patch | BG, EP | — |
<!-- END GENERATED -->

## Routing meanings

- **Native**: expose WebKit unchanged.
- **Native + patch**: keep WebKit's object identity and events, filling or
  normalizing only the listed contract gaps.
- **Emulated**: Crest owns the implementation, usually through the capability
  broker. Any conflicting dynamic WebKit API is hidden before the context loads,
  and Crest's implementation replaces a native property that appears in a later
  OS release rather than yielding to it. An emulated namespace always exposes
  the **complete** schema surface its reference browsers define, because
  extensions feature-detect on the namespace and then use the schema behind it
  in the same expression; the members Crest cannot deliver are routed **Presence
  only** and fail honestly rather than being absent. A partial namespace is
  worse than no namespace: it passes the detection and throws on the next
  member access, inside whatever awaited it. A shipped regression was exactly
  this — a password manager's worker bootstrap tested `sidePanel` and then
  called a member of the schema, so a one-member stub aborted the bootstrap and
  every initialization step after it, including the handler its popup asks for
  its data. The declared surface lives in `emulatedSurface`.
- **Presence only**: Crest supplies the member so feature detection succeeds,
  but cannot deliver it. Events register listeners and report them back while
  saying once that nothing will arrive; methods fail the way an unavailable
  capability fails — a rejected promise, or `runtime.lastError` for the callback
  form — because a no-op reports success for work that never happened. A native
  implementation shipping later wins.
- **Unavailable**: expose no false success. The matrix keeps the missing
  capability visible to product/support work.

Process abbreviations are **BG** (background worker/page), **EP** (extension
page or popup), **CS** (content script), and **DT** (DevTools page). A namespace
row describes the broad process boundary; individual schema members can be
narrower and are the next level of the matrix.

## Boundary notes

These are the boundaries behind each route. They are prose because they cannot
be derived from the matrix, and they are kept out of the generated block for
that reason.

- `action` / `browserAction` / `pageAction`: popup lifecycle and user-settings
  shape normalization.
- `alarms`: event delivery normalization for Manifest V3 listeners.
- `bookmarks`, `history`, `omnibox`, `sessions`, `topSites`: not implemented.
  Crest exposes none of its own stores or chrome surfaces to extensions yet.
- `commands`: manifest command normalization.
- `contextMenus` / `menus`: Crest registry and native webpage-menu
  presentation; contexts are normalized across the Chrome and Firefox schemas
  so one unsupported item cannot invalidate a complete menu replacement.
- `cookies`: constrained by reviewed host permissions.
- `declarativeNetRequest`: WebKit's content-rule translation is lossy.
- `devtools`: WebKit's subset only.
- `dom`: a Chrome/WebKit-specific surface for extension pages and content
  scripts.
- `downloads`: emulated through the capability broker for `downloads.download`
  only, and the broker applies Crest's own destination and risk policy rather
  than an extension-chosen path. Every other member the Chromium schema defines
  is present and **Presence only** — searching, pausing, erasing, the shelf, and
  the four events — so a package that detects the namespace can call them and
  gets a real failure instead of a missing function.
- `extension`: view and runtime identity normalization, restricted to the
  processes where the reference browsers expose those members.
- `i18n`: message lookup and empty-token normalization, even when the native
  namespace cannot be augmented in place.
- `identity`: `getRedirectURL` and `launchWebAuthFlow` are implemented against
  a Crest-owned authentication window on the Space's own website data store,
  so a `chromiumapp.org` flow completes the way it does in Chrome — including
  the silent `prompt=none` refresh an extension runs at startup. The
  Google-account members are not, because a Crest profile has no Google
  account: `getAccounts` answers with an empty list, `getProfileUserInfo` with
  an empty profile, `removeCachedAuthToken` and `clearAllCachedAuthTokens`
  succeed against an empty cache, and `getAuthToken` refuses in Chrome's own
  words. `onSignInChanged` keeps a real registry and never fires.
- `idle`: broker-backed macOS session and input state with query, detection
  interval, and transition events. Firefox's `getAutoLockDelay` is **Presence
  only**.
- `management`: `getSelf` only. There is no cross-extension discovery or
  mutation. `getAll`, `get`, `setEnabled`, `uninstall`, the permission-warning
  queries, the app members, and the four lifecycle events are present and
  **Presence only**: they exist so the namespace is a complete object, and they
  refuse. They moved from Unavailable to Presence only for that reason — an
  absent member in a namespace an extension has already detected is a
  `TypeError`, not a graceful degradation.
- `notifications`: broker-backed native notifications covering create, update,
  clear, query, click, button, and close. `onPermissionLevelChanged` and
  `onShowSettings` are **Presence only** — macOS owns both, so Crest has no
  source that can fire them.
- `offscreen`: emulated. Crest hosts a hidden document at the URL the extension
  bundles and drives its lifecycle through the capability broker, and the
  compatibility runtime overlays the namespace so exactly one implementation
  owns the document. WebKit trunk enabled a native `offscreen` implementation
  on 2026-08-28 behind a pref that defaults on, so the row moved from
  Unavailable to **Partial** — which is what arms the hiding rule, since it
  only fires for a namespace WebKit actually provides. A package that requests
  the `offscreen` permission therefore gets `browser.offscreen` removed from
  the native surface and Crest's emulation in its place. Without that move, a
  macOS 27 update would have replaced a broker-managed document lifecycle with
  an untested native one on the strength of a property changing from
  `undefined` to present.
- **Presence only** (a route, not a namespace): Crest supplies a member so a
  portable package's feature detection takes the same branch it takes in
  Chrome, while having no source that can deliver it. The object keeps a real
  listener registry — `hasListener` answers for a listener that was actually
  added — and warns once, per event, that nothing will arrive. A method routed
  this way is not a no-op: it rejects, or reports through `runtime.lastError`,
  because success for work that never happened leaves an extension waiting
  forever on it. It does not own its member: unlike **Emulated**, a native
  implementation shipping later displaces the placeholder rather than being
  displaced by it.
- **Emulated surface completeness** (a rule, not a namespace): every namespace
  routed **Emulated** publishes the whole member list its reference schema
  defines — `emulatedSurface` in the matrix — because feature detection is on
  the namespace and the schema behind it is then assumed. The members Crest
  implements answer for real; the rest are **Presence only**. Nothing about
  this makes a missing capability work: it makes the failure land at the call
  the extension made rather than as a `TypeError` inside its bootstrap.
- `permissions`: internal transport grants are hidden from extension-authored
  queries. Optional permissions for Crest-emulated APIs are not re-authorized
  after load yet.
- `privacy`: the complete `network` / `services` / `websites` group shape with
  conservative read-only settings reported as not controllable, so no extension
  is told it changed a system policy.
- `runtime`: native Port and message object identity is preserved.
  `runtime.getManifest()` returns the authored manifest rather than Crest's
  temporary worker redirection.
- `scripting`: enum and member normalization; injection itself remains native.
- `sidePanel` / `sidebarAction`: Crest hosts the extension document in a
  trailing split-row card on macOS. Both namespaces publish their complete
  implemented schema; WebKit's partial namespaces remain hidden. Chrome's API
  requires Manifest V3 and `sidePanel`; Firefox's requires `sidebar_action`.
  Opening requires a user gesture. Firefox close and toggle do too. Path icons
  are supported; `setIcon({imageData})` rejects explicitly. The panel is not a
  tab. One selected panel remains open across tabs within its Space; choosing
  another extension replaces it. Space changes hide and restore each Space's
  selection. Closing, replacing, or locking unloads its document, and relaunch
  starts closed. Only action behavior, width, and last-used extension persist.
  A tab-scoped open retains its initial resource across tab switches. Native
  tab queries and activation events remain available, but Crest does not rewrite
  the extension's captured tab IDs or reload its conversation to retarget it.
  Extensions that bind a conversation to the opening tab or group therefore
  keep that context. Unchanged Claude 1.0.90 exhibits this limitation in live
  testing; automatic conversation retargeting is not supported.
  ChatGPT 1.26.827.12125 instead observes activation and keys its own conversation
  router by active tab ID. Live tab switching restores each tab's prior chat.
  Keeping one host document does not override either vendor's conversation model.
  Top-level web links open a browser tab. A private navigation content controller
  isolates sidepanel/offscreen documents and their web frames from shared extension
  scripts, styles, and content rules while retaining the owner's native runtime.
  This uses guarded WebKit SPI; hosted documents fail closed without it. The
  hosted-page CSP compatibility policy remains a separate limitation.
- `storage`: native local, sync, session, and managed areas with cross-context
  and event normalization.
  DOM `window.localStorage` is separate from `chrome.storage.local`. WebKit's
  persistent DOM storage has a fixed 5 MiB limit; the extension's
  `unlimitedStorage` permission does not raise it. ChatGPT's Statsig cache has
  exceeded that limit in isolated testing. Manual cache recovery restored tools,
  but Crest has no durable quota workaround and does not evict vendor keys
  automatically. See [WebKit's storage implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/NetworkProcess/storage/LocalStorageManager.cpp)
  and [the permission contract](https://developer.apple.com/documentation/webkit/wkwebextension/permission/unlimitedstorage).
- `tabs` / `windows`: Crest's tab and window adapters are authoritative; a
  single-URL popup request can become a native Crest auxiliary window.
- `test`: a reference-browser internal namespace that is never exposed.
- `userScripts`: dynamic user-script registration is not implemented.
- `webNavigation`: frame queries and the core load lifecycle remain native.
  WebKit 27 omits four standard events, which Crest routes **Presence only**
  until native dispatch exists.
- `webRequest`: child-document loads are normalized from WebKit's contradictory
  `main_frame` value to `sub_frame` when `parentFrameId` identifies a parent.
  Blocking responses remain unavailable and `onAuthRequired` is hidden rather
  than answered.

## Extension-process contract

1. **Background worker/page** owns lifecycle events, long-lived Ports, alarms,
   native broker access, and authoritative shared state.
2. **Extension pages/popups** use the same extension origin and native runtime
   identity as the background. Popup presentation is a browser surface, not a
   substitute runtime.
3. **Content scripts** retain WebKit's isolated world and native runtime
   messaging. Crest never exposes the native capability broker directly to a
   webpage or content world.
4. **Webpage/main world** receives only extension-authored DOM changes. Crest's
   own Passwords UI must be disabled during third-party password-manager
   validation so the two implementations cannot be confused.

The compatibility runtime may receive an internal WebKit <code>nativeMessaging</code>
grant solely to reach Crest's capability-broker identifier. That transport is a
separate authorization bit: it never authorizes an external native host. An
external host still requires an authored, user-granted <code>nativeMessaging</code>
permission and a verified signed package identity.

## End-to-end acceptance

The matrix is accepted through real browser behavior, not fixture-specific
success. Arc is the Chromium reference on this machine; Safari or Firefox is
used when the extension ships a platform-specific package.

For each target extension, compare:

1. cold launch and first navigation;
2. toolbar popup and full extension window;
3. authentication and persisted unlock;
4. background-to-popup and content-to-background messaging;
5. page matching, field injectors, menu placement, and autofill;
6. dark/light appearance;
7. idle CPU after the UI settles;
8. relaunch without reload, manual background warming, or repeated login.

The initial target set is Dark Reader, uBlock Origin, Bitwarden, and LastPass.
An API failure updates this matrix at the failing namespace/member and process
boundary before implementation changes are made.
