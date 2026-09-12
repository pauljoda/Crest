# Desktop Picture in Picture

Crest uses macOS's native video Picture in Picture presentation, including its
system window and controls. Automatic entry is enabled by default and can be
disabled in Settings → General → Video. Manual entry remains available when
automatic entry is disabled.

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

Source investigation used WebKit commit
`824d434d74a36754b75566c9939b0aef46e21757`. The links above follow upstream so
future investigations can compare changes.

## Ownership and tab transitions

`BrowserPagePool` requests automatic entry only for pages leaving the visible
tab set. Moving focus between cards in a visible split does not enter PiP.
If multiple cards leave together, the focused card is considered first.
Returning to the source tab ends the PiP session Crest started automatically;
it preserves a session the user entered manually.

One application-wide coordinator serves all windows and private Spaces.
It reserves the slot before dispatching a request, rejects requests while a
registered page is active or a request is pending, and checks macOS PIPAgent
window metadata for an existing system session. A running PIPAgent alone is
insufficient: it remains running after PiP closes. The check reads public
window metadata without capturing the screen or requesting Screen Recording
permission. It is a best-effort snapshot: macOS provides no public atomic PiP
reservation shared with other applications, and the agent identity is an OS
implementation detail.

The page controller tracks the exact frame, document, video, and automatic
request ID. JavaScript revalidates the player synchronously immediately before
requesting PiP through WebKit's native evaluation context. A promise result,
native presentation callback, and four-second timeout settle the request.
Returning during entry cancels the matching request and returns a late
presentation inline. Automatic cancellation never targets an unrelated
manually entered session.

An active or pending PiP presentation protects the source page from automatic
unloading, including when playback is paused. The original WKWebView and
media pipeline remain alive while its view is detached. Closing, explicitly
unloading, navigating, or terminating the source ends its presentation.
Locking a protected Space also closes its video, including a Space in the
background.

## Recognizing an interactive player

The bridge runs in a named isolated content world in every frame. Popups may
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

Ordinary tests cover default preferences, slot reservation/cancellation,
manual occupancy, DOM player permutations, frame routing, and decorative
embeds. Live checks also exercise WebKit's enabled native PiP context-menu
item with automatic entry disabled, background Space locking, rapid return
during entry, competing videos, source residency, and the YouTube watch player.
Live tests are opt-in because they open actual system PiP windows:

```sh
TEST_RUNNER_CREST_PIP_LIVE_TESTS=1 \
TEST_RUNNER_CREST_PIP_WEBSITE_TESTS=1 \
xcodebuild -project Crest.xcodeproj -scheme Crest \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:CrestTests/BrowserAutomaticPictureInPictureTests \
  -only-testing:CrestTests/BrowserPictureInPicturePlayerTests \
  -only-testing:CrestTests/BrowserPictureInPictureLiveTests test
```

The `TEST_RUNNER_` prefix passes the flags into the XCTest app process. Close
any existing PiP session first; live tests skip when the slot is already in
use. Website tests additionally require network access and may be affected by
consent pages, ads, account requirements, and changes to the selected video.

## Media pipeline

Copying `video.currentSrc` into a new native player would discard the original
pipeline. It cannot generally recreate Media Source Extensions, encrypted
media, authentication, or site controls. Native PiP keeps the original WebKit
page and media pipeline alive.
