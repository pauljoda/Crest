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
- **Emulated** is implemented by Crest, with native broker access scoped to the extension's reviewed permissions.
- **Partial** is useful but does not match every Chrome or Firefox semantic.
- **Unavailable** is intentionally absent; Crest does not return false success.

### Actions, runtime, and browser UI

| API | Chrome / Firefox | WebKit substrate | Crest route | Current boundary |
| --- | --- | --- | --- | --- |
| <code>action</code>, <code>browserAction</code>, <code>pageAction</code> | Native | Native | Native + patch | Popup lifecycle and user-settings shape normalization. |
| <code>commands</code> | Native | Native | Native + patch | Manifest command normalization. |
| <code>contextMenus</code> / <code>menus</code> | Native | Native | Native + patch | Crest registry and native webpage-menu presentation; contexts are normalized across Chrome and Firefox. |
| <code>notifications</code> | Native | Partial | Emulated | Native notifications plus create, update, clear, query, click, button, and close events. |
| <code>windows</code> | Native | Native | Native + patch | Tabs and primary windows are native adapters; a single-URL popup request can become an auxiliary Crest window. |
| <code>offscreen</code> | Chrome native / Firefox unavailable | New, conditional native API | Native | Uses WebKit's document implementation; Crest does not substitute a hidden page. |
| <code>sidePanel</code> / <code>sidebarAction</code> | Platform-specific | Partial | Unavailable | Crest has no extension-owned sidebar surface yet. |
| <code>omnibox</code> | Native | Unavailable | Unavailable | No extension keyword surface yet. |

### Runtime, lifecycle, and state

| API | Chrome / Firefox | WebKit substrate | Crest route | Current boundary |
| --- | --- | --- | --- | --- |
| <code>runtime</code> | Native | Native | Native + patch | Authored manifest/base URL, update-check shape, and worker boundaries are normalized without replacing native messaging or Port objects. |
| <code>extension</code> | Native | Native | Native + patch | View and background-page members are restricted to the processes where reference browsers expose them. |
| <code>alarms</code> | Native | Native | Native + patch | MV3 listener and alarm delivery normalization. |
| <code>idle</code> | Native | Unavailable | Emulated | macOS session/input state with query, interval, and transition events. |
| <code>management</code> | Native | Unavailable | Emulated, partial | <code>getSelf</code> only; no cross-extension discovery or mutation. |
| <code>storage</code> | Native | Native | Native + patch | Native local, sync, session, and managed areas with cross-context/event normalization. |
| <code>permissions</code> | Native | Native | Native + patch | Internal transport grants are hidden from extension-authored permission queries. Live optional grants for Crest-emulated APIs are not fully supported yet. |
| <code>i18n</code> | Native | Native | Native + patch | Message lookup and empty-token normalization. |

### Tabs, navigation, and requests

| API | Chrome / Firefox | WebKit substrate | Crest route | Current boundary |
| --- | --- | --- | --- | --- |
| <code>tabs</code> | Native | Native | Native + patch | Crest tab/window adapters are authoritative; query/get/message results are normalized. |
| <code>webNavigation</code> | Native | Partial | Native + patch, partial | Frame queries and core lifecycle are native. Four standard events are presence-only until Crest has engine-backed dispatch. |
| <code>webRequest</code> | Native | Observe-only | Native + patch, partial | Request metadata and child-frame type are normalized. Blocking responses and credential-supplying authentication are unavailable. |
| <code>declarativeNetRequest</code> | Native | Partial | Native, partial | WebKit translates supported rules into content blocking; the translation is not lossless. |
| <code>cookies</code> | Native | Native | Native | Constrained by reviewed host permissions. |
| <code>history</code> | Native | Unavailable | Unavailable | Not implemented. |
| <code>sessions</code> | Native | Unavailable | Unavailable | Not implemented. |
| <code>topSites</code> | Native | Unavailable | Unavailable | Not implemented. |

### Page code, data, and platform services

| API | Chrome / Firefox | WebKit substrate | Crest route | Current boundary |
| --- | --- | --- | --- | --- |
| <code>scripting</code> | Native | Native | Native + patch | Execution-world enum and member normalization; actual injection remains native. |
| <code>userScripts</code> | Native | Unavailable | Unavailable | Dynamic user-script registration is not implemented. |
| <code>dom</code> | Chrome/WebKit only | Native | Native | Extension-page and content-script surface. |
| <code>privacy</code> | Native | Unavailable | Emulated, partial | Complete group shape with conservative values reported as <code>not_controllable</code>; no false claim of changing system policy. |
| <code>bookmarks</code> | Native | Unavailable | Unavailable | Not implemented. |
| <code>downloads</code> | Native | Unavailable | Unavailable | Extension-initiated downloads and vault export are not implemented. |
| <code>identity</code> | Chrome native / Firefox partial | Unavailable | Unavailable | Browser-specific OAuth redirect contract is not implemented. |
| <code>devtools</code> | Native | Partial | Native, partial | WebKit's subset only. |

## What this coverage means

Crest currently routes **36 namespace contracts** through one executable matrix. Twenty-five are available in some form and eleven are intentionally unavailable. The strongest coverage is around the flows used by password managers, page modifiers, and extension popups: runtime messaging, storage, tabs, injection, actions, auxiliary windows, permissions, notifications, menus, and lifecycle.

The remaining gaps cluster around three areas: browser-owned data stores such as bookmarks/history/downloads; browser-chrome surfaces such as side panels and omnibox; and request interception semantics WebKit does not expose. Those gaps are documented instead of being replaced with extension-specific shims or successful no-ops.

For the implementation-level contract and pinned Chromium, Firefox, WebKit, and SDK revisions, see the [technical API matrix](https://github.com/pauljoda/Crest/blob/main/Documentation/ExtensionAPICompatibilityMatrix.md). For package-specific native limits, continue with [Direct build, App Store, and native companions](./native-companion-limits.md).
