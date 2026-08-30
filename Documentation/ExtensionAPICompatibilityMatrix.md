# Crest WebExtension API compatibility matrix

This document records the browser contract Crest intends to expose to portable
Chrome and Firefox WebExtensions. The executable source of truth is
`BrowserExtensionAPICompatibilityMatrix`; package preparation, capability
broker authorization, and WebKit API hiding must derive from that matrix rather
than from extension identities, source scans, or opportunistic
`existing === undefined` checks.

## Pinned specification inputs

- Chromium extension schemas and feature gates:
  [`209681af9aaea48aa172a1a9eb1eb2cdc63c1e67`](https://chromium.googlesource.com/chromium/src/+/209681af9aaea48aa172a1a9eb1eb2cdc63c1e67/chrome/common/extensions/api/)
  and [common schemas](https://chromium.googlesource.com/chromium/src/+/209681af9aaea48aa172a1a9eb1eb2cdc63c1e67/extensions/common/api/).
- Firefox WebExtension schemas:
  [`5836a062726f715fda621338a17b51aff30d0a8c`](https://github.com/mozilla/gecko-dev/tree/5836a062726f715fda621338a17b51aff30d0a8c/toolkit/components/extensions/schemas).
- WebKit extension IDL/runtime:
  [`e4856c6696f58bae6f5cf1e864d0550f9eff09f8`](https://github.com/WebKit/WebKit/tree/e4856c6696f58bae6f5cf1e864d0550f9eff09f8/Source/WebKit/WebProcess/Extensions/API).
- Shipping interface used by this pass: Xcode 27.0 (27A5237l), macOS 27.0
  SDK. The installed `WKWebExtensionContext.h` is authoritative for the host
  API Crest can call.

The revisions are intentionally pinned. Updating a source revision is a
deliberate compatibility review, not a background behavior change.

## Routing meanings

- **Native**: expose WebKit unchanged.
- **Native + patch**: keep WebKit's object identity and events, filling or
  normalizing only the listed contract gaps.
- **Emulated**: Crest owns the implementation, usually through the capability
  broker. Any conflicting dynamic WebKit API is hidden before the context loads.
- **Unavailable**: expose no false success. The matrix keeps the missing
  capability visible to product/support work.

Process abbreviations are **BG** (background worker/page), **EP** (extension
page or popup), **CS** (content script), and **DT** (DevTools page). A namespace
row describes the broad process boundary; individual schema members can be
narrower and are the next level of the matrix.

## Namespace matrix

| Namespace | Chrome | Firefox | WebKit | Crest route | Processes | Current boundary |
| --- | --- | --- | --- | --- | --- | --- |
| action / browserAction / pageAction | Native | Native | Native | Native + patch | BG, EP | Popup lifecycle and user settings normalization |
| alarms | Native | Native | Native | Native + patch | BG, EP | Event delivery normalization |
| bookmarks | Native | Native | Unavailable | Unavailable | BG, EP | Not implemented |
| commands | Native | Native | Native | Native + patch | BG, EP | Manifest command normalization |
| contextMenus / menus | Native | Native | Native | Native + patch | BG, EP | Crest registry and native menu presentation |
| cookies | Native | Native | Native | Native | BG, EP | Host permission constrained |
| declarativeNetRequest | Native | Native | Partial | Native | BG, EP | WebKit content-rule translation is lossy |
| devtools | Native | Native | Partial | Native | DT | WebKit subset only |
| dom | Native | Unavailable | Native | Native | EP, CS | WebKit/Chrome-specific surface |
| downloads | Native | Native | Unavailable | Unavailable | BG, EP | Vault export is not yet supported |
| extension | Native | Native | Native | Native + patch | BG, EP, CS | View/runtime identity normalization |
| history | Native | Native | Unavailable | Unavailable | BG, EP | Not implemented |
| i18n | Native | Native | Native | Native + patch | BG, EP, CS | Message lookup normalization |
| identity | Native | Partial | Unavailable | Unavailable | BG, EP | Chromium redirect contract not implemented |
| idle | Native | Native | Unavailable | Emulated | BG, EP | Capability broker |
| management | Native | Native | Unavailable | Emulated, partial | BG, EP | `getSelf`; no cross-extension mutation |
| notifications | Native | Native | Partial/test stub | Emulated | BG, EP | Capability broker and native notifications |
| offscreen | Native | Unavailable | Partial/new | Native | BG, EP | Uses WebKit's conditional document implementation; Crest does not substitute a hidden page |
| omnibox | Native | Native | Unavailable | Unavailable | BG, EP | Not implemented |
| permissions | Native | Native | Native | Native + patch | BG, EP | Internal transport grants are hidden; optional emulated permissions are not re-authorized after load yet |
| privacy | Native | Native | Unavailable | Emulated, partial | BG, EP | Complete `network` / `services` / `websites` group shape with conservative read-only, uncontrollable settings |
| runtime | Native | Native | Native | Native + patch | BG, EP, CS | Preserve native Port/message object identity |
| scripting | Native | Native | Native | Native + patch | BG, EP | Enum/member normalization |
| sessions | Native | Native | Unavailable | Unavailable | BG, EP | Not implemented |
| sidePanel / sidebarAction | Native/Unavailable | Unavailable/Native | Partial | Unavailable | BG, EP | No Crest sidebar surface yet |
| storage | Native | Native | Native | Native + patch | BG, EP, CS | Native stores with event/session normalization |
| tabs | Native | Native | Native | Native + patch | BG, EP | Crest tab/window adapters are authoritative |
| topSites | Native | Native | Unavailable | Unavailable | BG, EP | Not implemented |
| userScripts | Native | Native | Unavailable | Unavailable | BG, EP | Dynamic script registration is not implemented |
| webNavigation | Native | Native | Partial | Native + patch | BG, EP | Frame queries and the core load lifecycle remain native; WebKit 27 omits four standard events, which Crest exposes as presence-only registration fallbacks until native dispatch exists |
| webRequest | Native | Native | Observe-only | Native + patch, partial | BG, EP | Child-document loads are normalized from WebKit's contradictory `main_frame` value to `sub_frame` when `parentFrameId` identifies a parent; blocking and credential-supplying auth remain unavailable |
| windows | Native | Native | Native | Native + patch | BG, EP | Popup windows broker to Crest-native windows |

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
