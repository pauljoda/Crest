---
title: Extension compatibility matrix
description: Known extension results and Crest's Chrome, Firefox, Safari, and WebExtension API support.
slug: /extension-api-compatibility
sidebar_label: Full compatibility matrix
sidebar_position: 8
hide_table_of_contents: true
keywords: [extension compatibility, WebExtension API, Chrome extension, Firefox extension, Safari extension, Bitwarden, LastPass, Dark Reader, uBlock Origin]
---

# Extension compatibility matrix

This is the current measured support snapshot for Crest on Mac. **Verified** means the listed workflow was exercised in the real extension and browser—not that every version, site, or optional feature is guaranteed.

<table className="guide-responsive-table guide-compatibility-table">
  <thead>
    <tr><th>Extension</th><th>Package tested</th><th>Status</th><th>What is known to work</th><th>Current limit</th></tr>
  </thead>
  <tbody>
    <tr><td data-label="Extension">Bitwarden</td><td data-label="Package tested">Chrome 2026.8.0</td><td data-label="Status"><strong>Verified end to end</strong></td><td data-label="What is known to work">Device verification, login, vault, relaunch unlock, popout window, page injector, and autofill.</td><td data-label="Current limit">No known limit in the tested workflow.</td></tr>
    <tr><td data-label="Extension">LastPass</td><td data-label="Package tested">Chrome 4.155.1</td><td data-label="Status"><strong>Verified end to end</strong></td><td data-label="What is known to work">Login, vault, relaunch persistence, matching-item popup, in-field integration, and autofill.</td><td data-label="Current limit">No known limit in the tested workflow.</td></tr>
    <tr><td data-label="Extension">Dark Reader</td><td data-label="Package tested">Firefox 4.9.129</td><td data-label="Status"><strong>Verified core workflow</strong></td><td data-label="What is known to work">Background startup, full action controls, page injection, toggling, and site appearance.</td><td data-label="Current limit">Advanced behavior on every site and theme combination is not exhaustively certified.</td></tr>
    <tr><td data-label="Extension">uBlock Origin</td><td data-label="Package tested">Firefox 1.73.0</td><td data-label="Status"><strong>Partial—engine limited</strong></td><td data-label="What is known to work">MV2 background page, popup controls and live statistics, cosmetic/page integration, and child-frame request classification.</td><td data-label="Current limit">WebKit reports requests but does not consume blocking <code>webRequest</code> listener responses, so cancellation, redirect, header mutation, and authentication parity are unavailable.</td></tr>
    <tr><td data-label="Extension">uBlock Origin Lite</td><td data-label="Package tested">Chrome 2026.812.1211</td><td data-label="Status"><strong>Startup verified</strong></td><td data-label="What is known to work">The Declarative Net Request package verifies, installs, and starts cleanly.</td><td data-label="Current limit">Full filter-list and site-by-site behavior has not been certified.</td></tr>
    <tr><td data-label="Extension">SponsorBlock</td><td data-label="Package tested">Chrome 6.1.6</td><td data-label="Status"><strong>Startup verified</strong></td><td data-label="What is known to work">Package verification, installation, and background startup.</td><td data-label="Current limit">The complete YouTube workflow has not been certified.</td></tr>
    <tr><td data-label="Extension">1Password</td><td data-label="Package tested">Chrome 8.12.32.33</td><td data-label="Status"><strong>Native companion pending</strong></td><td data-label="What is known to work">Worker startup, setup UI, account navigation, native-host launch, and browser-authorization handoff.</td><td data-label="Current limit">Pairing and autofill require a Developer ID signed Crest release trusted through 1Password's Add Browser flow.</td></tr>
    <tr><td data-label="Extension">Grammarly</td><td data-label="Package tested">Chrome 14.1320.0</td><td data-label="Status"><strong>Partial</strong></td><td data-label="What is known to work">The worker loads.</td><td data-label="Current limit">Account-cookie access and an initial tab-creation request still fail.</td></tr>
    <tr><td data-label="Extension">React Developer Tools</td><td data-label="Package tested">Chrome 7.0.1</td><td data-label="Status"><strong>Partial</strong></td><td data-label="What is known to work">Package installation and startup.</td><td data-label="Current limit">WebKit does not provide the requested isolated execution-world behavior.</td></tr>
    <tr><td data-label="Extension">Tampermonkey</td><td data-label="Package tested">Chrome 5.5.0</td><td data-label="Status"><strong>Partial</strong></td><td data-label="What is known to work">Package installation and partial background startup.</td><td data-label="Current limit">WebKit rejects its <code>tabs.onUpdated</code> startup registration.</td></tr>
    <tr><td data-label="Extension">iCloud Passwords</td><td data-label="Package tested">Chrome 3.3.0</td><td data-label="Status"><strong>Apple entitlement pending</strong></td><td data-label="What is known to work">The package and worker start.</td><td data-label="Current limit">Apple's helper requires a managed Web Browser Public Key Credential entitlement that Crest does not currently have.</td></tr>
  </tbody>
</table>

## Status meanings

- **Verified end to end**: the important signed-in workflow, page integration, and relaunch behavior were exercised directly.
- **Verified core workflow**: the extension's central browser behavior works, but its full option and site matrix was not exhaustively tested.
- **Startup verified**: the package verifies, installs, loads, and starts without a recorded runtime failure; deeper behavior is not certified.
- **Partial**: useful behavior works, with a known missing API or platform boundary.
- **Engine limited**: the missing behavior requires WebKit support that Crest cannot supply safely from browser-app code.

## Package and process support

| Extension kind | Crest support | Implementation boundary |
| --- | --- | --- |
| Chrome Manifest V3 | Supported | Keeps the service worker native. Crest loads a content-addressed compatibility bootstrap before the authored worker while preserving WebKit's runtime, Port, event, and sender identity. |
| Chrome Manifest V2 | Supported | Keeps background pages or scripts in their authored document process and layers compatibility before package code. |
| Firefox WebExtensions | Supported | Mozilla-signed packages retain their published identity and Firefox reference environment while using the shared compatibility routes. |
| Content scripts | Supported | Run in WebKit's isolated world; messaging and sender metadata remain engine-owned. Crest's private native broker is not exposed to webpages. |
| Popups and extension pages | Supported | Use the extension's WebKit configuration and origin. Action popups remain browser surfaces; requested single-page popup windows can open as native Crest auxiliary windows. |
| Safari Web Extensions | Native WebKit path | Run without the Chrome/Firefox preparation layer. Safari app discovery does not make the containing app's native handler portable. |
| Native companion extensions | Conditional | Only verified signed store identities can resolve external native hosts, and only when the extension requested and received <code>nativeMessaging</code>. |
| Unpacked extensions | Development support | Load through the shared compatibility layer, but cannot reach an external native companion. |
| Safari content blockers and legacy Safari App Extensions | Unsupported | These are different extension formats, not portable WebExtensions. |

## WebExtension API support

The route describes who owns the result:

- **Native** keeps WebKit's implementation unchanged.
- **Native + patch** preserves WebKit object identity while filling or normalizing a specific contract gap.
- **Emulated** is implemented by Crest, with native broker access scoped to the extension's reviewed permissions. An emulated namespace always presents its complete schema, because extensions check for the namespace and then use everything behind it; the parts Crest cannot do report a clear error instead of being missing.
- **Unavailable** is intentionally absent; Crest does not return false success.

The two tables below are generated directly from Crest's executable routing matrix, so they describe the shipping build rather than a hand-maintained summary. Plain-language limits follow them.

{/* BEGIN GENERATED: BrowserExtensionAPICompatibilityMatrix */}
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
| `identity` | Native | Partial | Unavailable | Unavailable | BG, EP | `identity`, `identity.email` | `identity`, `identity.email` | — |
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
| `tabGroups.onMoved` | Unavailable | Presence only | BG, EP | — |
| `tabGroups.onRemoved` | Unavailable | Emulated | BG, EP | — |
| `tabGroups.onUpdated` | Unavailable | Emulated | BG, EP | — |
| `tabGroups.query` | Unavailable | Emulated | BG, EP | — |
| `tabGroups.update` | Unavailable | Emulated | BG, EP | — |
| `tabs.get` | Native | Native + patch | BG, EP | — |
| `tabs.group` | Unavailable | Emulated | BG, EP | — |
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
{/* END GENERATED */}

### Where the boundaries are

- **Browser data stores.** Bookmarks, history, top sites, and sessions are not exposed to extensions at all.
- **Downloads.** An extension can start a download through <code>downloads.download</code>; Crest applies its own destination and safety policy. The rest of the namespace, including search and download history, is present but reports that Crest cannot do it, so an extension gets an error rather than a broken page.
- **Offscreen documents.** Crest hosts the hidden document itself, using the page the extension bundles, so Chrome extensions that depend on an offscreen worker keep working.
- **Side panels.** On macOS, Chrome <code>sidePanel</code> and Firefox <code>sidebarAction</code> open an extension-owned card beside your tabs. You can resize or close it, and choose another available extension from its title. Closing unloads the panel; restarting Crest leaves it closed. Firefox path icons work, but image-data icons are not supported.
- **Request blocking.** WebKit reports requests but does not consume blocking <code>webRequest</code> responses, so cancellation, redirection, header mutation, and authentication parity are unavailable. Declarative rules are translated by WebKit, and that translation is not lossless.
- **Sign-in redirects.** <code>identity.launchWebAuthFlow</code> needs a browser-owned authentication window Crest does not have yet.
- **Extension management.** An extension can read its own record. Listing, enabling, or removing other extensions is refused.
- **Keyword search.** There is no extension omnibox keyword surface.

## What this coverage means

Crest currently routes **37 namespace contracts** and 134 individual members through one executable matrix. Twenty-nine namespaces are available in some form and eight are intentionally unavailable. Coverage includes runtime messaging, storage, tabs, tab groups, injection, actions, auxiliary windows, side panels, permissions, notifications, menus, and lifecycle. API coverage alone does not certify every extension's account or native-companion workflow.

The remaining gaps cluster around browser-owned data stores such as bookmarks, history, and sessions; the extension omnibox; and request interception semantics WebKit does not expose. Those gaps are documented instead of being replaced with extension-specific shims or successful no-ops.

For the implementation-level contract and pinned Chromium, Firefox, WebKit, and SDK revisions, see the [technical API matrix](https://github.com/pauljoda/Crest/blob/main/Documentation/ExtensionAPICompatibilityMatrix.md). For package-specific native limits, continue with [Direct build, App Store, and native companions](./native-companion-limits.md).
