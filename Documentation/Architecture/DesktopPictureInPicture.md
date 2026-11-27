# Desktop Picture in Picture

Crest hosts WebKit and Chromium video in the same floating Picture in Picture
window, with playback, return, settings and close controls. Drag the window
to place it freely, flick it toward a corner to snap it there, or drag from a
resize cursor at an edge or corner. The settings button opens General →
Picture in Picture in Crest’s Settings tab. The optional border uses the
source Space’s theme and the device’s window border width. The Settings
preview updates as you change the border or choose square corners. The same
section has separate automatic entry options for switching tabs, switching apps, and
leaving Crest's macOS desktop. Tab switching and returning video on focus are
enabled by default. Site Controls → Site Settings can block automatic entry
for a site in the page's Space. Manual entry is available regardless of these
settings.

The Mac shell receives the live video view from each engine through the native
picture-in-picture presentation entry point. It preserves the engine's playback
and presentation callbacks while hosting the view in its own AppKit panel.
Placement, gesture state and border appearance belong to the shell.
The panel refreshes the hosted video at its settled size and after app or
desktop transitions, including transitions that leave its geometry unchanged.
The core owns behavior preferences and routes the return to the source page. When the presentation
bridge is unavailable, the system presenter handles the video.

## WebKit integration

Desktop WebKit exposes the JavaScript PiP API while separately disabling PiP
media presentation by default for embedders. Thus
`document.pictureInPictureEnabled` and the existence of
`requestPictureInPicture()` do not establish that a WKWebView can present it.
Requests can fail with `NotSupportedError` even when those APIs are present.

WebKit's own MiniBrowser enables the desktop preference through
`-[WKPreferences _setAllowsPictureInPictureMediaPlayback:]`.
`BrowserDesktopPictureInPictureAccess` resolves this selector at runtime and
uses a typed implementation pointer, following Crest's existing inspector
access pattern. The preference is enabled before constructing each page's
WKWebView, including adopted popup configurations. Missing SPI fails closed.
The iOS configuration property with a similar name is unavailable on macOS.

Crest's direct-distribution Mac app uses hardened runtime without App Sandbox.

Reference implementation and definitions:

- [MiniBrowser's preferences](https://github.com/WebKit/WebKit/blob/main/Tools/MiniBrowser/mac/AppDelegate.m)
- [WKPreferences desktop SPI](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKPreferencesPrivate.h)
- [WebKit preference defaults](https://github.com/WebKit/WebKit/blob/main/Source/WTF/Scripts/Preferences/UnifiedWebPreferences.yaml)
- [WebKit native context-menu eligibility](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/page/ContextMenuController.cpp)
- [Native PiP control routing](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/mac/VideoPresentationInterfaceMac.mm)
- [Inline-return delegate dispatch](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/Cocoa/UIDelegate.mm)

## Chromium integration

The Crest host implements Chromium's video overlay window interface through the
shared picture-in-picture presentation entry point. A dedicated compositor
embeds the video's Viz surface and sends its Core Animation layers to the panel.
The source tab keeps its own player and media session. Blink renders WebVTT
outside the video surface, so the host reads the showing caption and subtitle
cues from the active PiP document and displays their text in the floating view.
The host stops reading cues when the presentation ends. The playback
and close callbacks go through Chromium's existing video controller and window
manager. Crest resolves the system controller at runtime and Chromium declines
video PiP when it is unavailable. Website-created Document Picture in Picture
continues to host the document and its page-defined controls.

## Ownership and tab transitions

On tab switches, `BrowserPagePool` requests automatic entry for pages leaving
the visible tab set. Moving focus between cards in a visible split does not enter PiP.
If multiple cards leave together, the focused card is considered first.
Entering an unlocked empty Space or start page follows the same departure
lifecycle. Locking a protected Space withdraws its pages' pending automatic
requests. A departing WebKit page enters through Crest's bridge in the page,
after the player checks below. A departing Chromium page that is playing, and
not already in Picture in Picture, enters through the `EnterPictureInPicture`
page request, which asks Chromium's media session to move its video.

The Mac app observes app deactivation and macOS desktop departures. Both
routes ask the originating browser window's page pool to consider the focused
card first, then the other cards whose live views the window hosts. The
window's tab and Space must still match, and the Space must be unlocked.
The three choices are stored in the core's app preferences, and every
automatic request uses the same application-wide reservation.

With return on focus enabled, coming back to the source page ends its PiP
session and returns the video inline. The core applies this policy to both
engines. Each page reports its PiP
activity in its snapshot, and when a window shows a page again (by the sidebar,
a Space switch, a shortcut, the Dock menu or a window opening on it) the core
sends that page's engine `ExitPictureInPicture`. The active browser window
asks the same policy for the pages it presents when AppKit reports focus
returning to Crest. WebKit closes the page's media
presentations; Chromium closes its PiP window only when the page owns it. A page
that stays on screen, such as one the person floated without leaving it, keeps
its PiP. On return, WebKit cancels a pending automatic request. Chromium checks
for a late presentation and asks the core to redock it when the source is
still visible.

A Space this process may not show keeps no video on screen. When a protected
Space locks, on demand or as Crest goes to the background, or a Space is being
deleted or is gone, the core sends `ExitPictureInPicture` to every page of that
Space that reports PiP: its tabs' pages, in the background or not, and its Quick
Window and Peek pages. A page that reports PiP again while its Space is locked
is asked again at once. The rule is the core's, so it holds for both engines and
covers Chromium's document PiP for a page that owns the window. Private
workspaces never lock.

The player's return control reports `PictureInPictureReturned` for its page,
and the engine returns the video inline itself. WebKit reports it from
`_webViewFullscreenMayReturnToInline:` for an active, valid PiP source only.
Chromium's return control asks the page's `Browser` to activate it; the host's
`BrowserWindow` hands that ask to the binding, which reports it when the page
holds PiP or left it in the same task. The core then shows the page's tab in the
window that hosts the page, switching its Space and restoring its split group,
and publishes `WindowBroughtForward`. That window's page pool raises and
activates it without replacing the media pipeline. When the page's window has
closed, another window over its workspace shows the tab, preferring one that
shows the tab's Space; with none open, nothing happens, since the return never
opens a window. Closed tabs, locked Spaces and Spaces being deleted show
nothing, and a private page returns only within the private workspace. Ordinary
PiP dismissal does not request this routing.

One application-wide coordinator serves all windows and private Spaces.
It reserves the slot before dispatching a request, rejects requests while a
registered page is active or a request is pending, and checks macOS PIPAgent
window metadata for an existing system session. A running PIPAgent alone is
insufficient: it remains running after PiP closes. The check reads public
window metadata without capturing the screen or requesting Screen Recording
permission. It is a best-effort snapshot: macOS provides no public atomic PiP
reservation shared with other applications, and the agent identity is an OS
implementation detail.

The WebKit page controller tracks the exact frame, document, video, and
automatic request ID. JavaScript revalidates the player synchronously
immediately before requesting PiP through WebKit's native evaluation context. A promise result,
native presentation callback, and four-second timeout settle the request.
Returning during entry cancels the matching request and returns a late
presentation inline. Automatic cancellation never targets an unrelated
manually entered session.

An active or pending PiP presentation protects the source page from automatic
unloading, including when playback is paused. The original WKWebView and
media pipeline remain alive while its view is detached. Closing, explicitly
unloading, navigating, or terminating the source ends its presentation.
Locking a protected Space also closes its video, including a Space in the
background, as the core asks.

## Recognizing an interactive player

These checks apply to WebKit pages. The bridge runs in a named isolated content
world in every frame. Popups may
share a user-content controller, so scripts are installed once per controller
and messages are routed by their originating WKWebView.

Automatic entry requires all of the following:

- A playing video with current frame data and nonzero video dimensions.
- A rendered player at least 160 × 90 CSS pixels intersecting the viewport.
- WebKit presentation support and no website PiP opt-out.
- An interactive video and ancestor chain: hidden, inert, transparent,
  presentation-only, or pointer-disabled content is excluded.
- Native video controls, or a nearby custom control surface with multiple
  buttons and a timeline/slider. A player without a timeline can qualify after
  trusted interaction with multiple identifiable playback controls.

Muted playback and looping alone do not disqualify a real player. A lone
"pause background animation" button does not qualify decoration. Auto-hidden
custom controls are allowed, while controls removed with `display:none` are
excluded. A bounded media set is updated from DOM and playback events, with
coalesced state reports rather than periodic full-document polling.

Parents propagate iframe eligibility across frame boundaries. Each hop checks
the sender's Window identity, so a cross-origin player can account for its
embedding frame's presentation role and visibility. The parent messages carry
only eligibility, never media URLs or page contents.

An iframe with `role="presentation"` is excluded even when it embeds an
interactive video. Frame eligibility is evaluated separately from the player's
own controls.

Classification intentionally favors skipping an ambiguous player over opening
decorative video. Sites with unusual controls, closed shadow trees, or media
restrictions may need additional compatibility work. Manual PiP remains a
separate WebKit capability and is not subject to the automatic classifier.

## Validation

Retained tests cover slot reservation/cancellation, manual occupancy and DOM
player eligibility. The core's tests cover ending PiP when a page comes back on
screen, and the return control's routing to the owning window, Space and tab.

Exercise the actual macOS PiP controls in an isolated app with a disposable video
fixture on both engines. Check each automatic trigger independently, including
leaving a full-screen desktop, then check manual entry, Return to tab from
another tab, Space and browser window, coming back to the source tab by the
sidebar, a Space switch and a shortcut, ordinary Close, playback continuity, and
source navigation or closure. These native UI checks complement the core's
tests; a reported return does not establish that the native control sends it.

## Media pipeline

Copying `video.currentSrc` into a new native player would discard the original
pipeline. It cannot generally recreate Media Source Extensions, encrypted
media, authentication, or site controls. Native PiP keeps the original WebKit
page and media pipeline alive.

The Chromium adapter uses the same macOS controller WebKit uses for its
remote layer. Both engines own their live media and send the system a
presentation surface. Text tracks follow the engine's rendering of that
surface. See [WebKit's controller integration](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/mac/VideoPresentationInterfaceMac.mm).
