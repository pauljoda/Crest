# WebKit

The Mac side of the WebKit engine: the per-page adapter that owns the
`BrowserDesktopWebView`, its navigation and UI delegates, the content-script
bridges (link hover, link drag, link context, Picture in Picture, hosted
notifications), file upload access, Web Inspector, printing, the user agent,
WebKit feature flags, and the runtime store that decides which window
presents each tab's page.

## Goal

WebKit pages behave as the core decides, with every WebKit and AppKit call
for them kept in this folder and `CrestShared/Infrastructure/WebKit/`.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserWebKitPageAdapter.swift` | The desktop WebKit adapter for one page: web view, delegates, bridges, page controllers |
| `BrowserPage+WebKit.swift`, `BrowserPage+WKNavigationDelegate.swift`, `BrowserPage+WKUIDelegate.swift` | The page's WebKit delegate conformances |
| `BrowserDesktopWebView.swift`, `BrowserDesktopWebViewMenuHost.swift`, `BrowserPage+BrowserDesktopWebViewMenuHost.swift`, `NSMenu+WebKitItems.swift`, `NSUserInterfaceItemIdentifier+WebKitItems.swift` | The Mac web view and Crest's actions in its context menu |
| `BrowserDesktopWebKit.swift`, `BrowserPlatformWebKit.swift`, `BrowserPlatformUserAgent.swift` | What only Mac WebKit pages need, the shared seam resolved to it, the user agent |
| `BrowserPageRuntimeStore.swift`, `BrowserPagePool+WebKit.swift` | Which window presents each tab's page; a temporary workspace gets its own store |
| `BrowserLinkContextCapture.swift`, `BrowserLinkContextContentBridge.swift` | The web content a right-click landed on, for that one menu |
| `BrowserFileUploadAccess.swift` | Keeps file picker grants alive while WebKit hands paths to its processes |
| `BrowserWebInspectorAccess.swift`, `InspectorPanel+WebInspector.swift` | Web Inspector, docked in the window |
| `BrowserWebKitPageEngine+Printing.swift` | Printing a WebKit page |
| `BrowserHostedWebNotificationContentBridge.swift`, `BrowserPage+HostedWebNotifications.swift` | Wires a page to hosted web notifications |
| `FeatureFlags/` | WebKit feature flag registry, filter, store and persistence behind the Settings pane |
| `HostedNotifications/` | The notification bridge's messages: creation, closing, permission query, request and resolution |
| `LinkDrag/` | Dragging a link into Peek: content bridge and AppKit controller |
| `LinkHover/` | The hovered-link preview: bridge, controller, destination, message, state |
| `PictureInPicture/` | Automatic and manual Picture in Picture: script, bridge, page controller, access |

## Depends on

`CrestShared/Infrastructure/WebKit/` (`WebKitEngineBinding`, `BrowserWebKitPageEngine`,
`BrowserPageContentRuleSession`), `CrestMac/Infrastructure/Pages/` (`BrowserPage`,
`BrowserPageEngineAdapter`), WebKit and AppKit. Chromium pages use their own
adapter in `CrestEngines/Chromium/Apple/`.

## Rules

- Shared code never calls WebKit; only engine adapters do (skill, "Architecture").
- A bridge decodes a page's message once at the boundary into a typed message, never a dictionary or string match (skill, "Code style").
- File uploads validate reads in the host app and keep picker scopes until the page is removed (`Documentation/ARCHITECTURE.md`, "Credentials and privacy").
- WebKit's new-window view is returned synchronously; there is no deferred loading (`Documentation/LinkOpeningPolicy.md`, "Loading and residency").
- Picture in Picture follows `Documentation/Architecture/DesktopPictureInPicture.md`; content rules follow `Documentation/Architecture/ContentBlocking.md`.
- DevTools docks inside the window, never a window of its own (skill, "Windows and UI").

## Read next

`Documentation/ARCHITECTURE.md` ("Engine boundary"),
`Documentation/Architecture/DesktopPictureInPicture.md` ("WebKit integration"),
`CrestShared/Infrastructure/WebKit/`, then
`CrestMac/Infrastructure/WebKit/BrowserWebKitPageAdapter.swift`.
