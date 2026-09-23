# Chromium source preparation

`source.lock.json` pins the Chromium archive, ungoogled macOS revisions, upstream
patches, and Crest build adjustments. It records source preparation inputs. It
does not identify a released engine artifact or establish host capabilities.

The source build requires Apple Silicon, Xcode with the matching Metal toolchain,
Python 3.10 or newer with `schema`, Ninja, and Go. Keep the Chromium checkout and
products outside Crest. The source archive alone expands to roughly 10 GB;
toolchains and compilation products require additional space.

Clone the `ungoogledMac.repository` at the exact revision in the lock and initialize
its `ungoogled-chromium` submodule. Use a task-specific Python environment with
`schema` and `ninja` installed, and put that environment's `bin` directory on PATH.
Then run:

```sh
python Scripts/control-plane/prepare-chromium.py --upstream /absolute/upstream/checkout
python Scripts/control-plane/build-chromium-baseline.py \
  --source /absolute/upstream/checkout/build/src --jobs 4 --min-free-gib 15
```

Preparation refuses an existing `build/src` directory. `--verify-only` validates
the pinned inputs without modifying an existing preparation. If preparation fails,
inspect that step before resuming it; do not run upstream `build.sh` over existing
work because it removes the output directory.

The development build uses a non-component link, Apple's linker, and disabled
precompiled headers. It explicitly disables `dcheck_always_on` and
`enable_expensive_dchecks`: in this Chromium revision, `is_debug=false` alone
still enables those checks in a non-official build. V8 then also compiles debug
code and write-barrier verification. Use a separate diagnostic build when those
checks are needed; do not compare its benchmark scores with shipping browsers.
Changing these flags requires recompiling Chromium, not just the Swift framework.
For an existing prepared checkout, stop its build, then run
`configure-chromium.py --source /absolute/chromium/src --configuration development`
and rebuild with `build-chromium-baseline.py`. Configuration replaces the
preset-owned GN arguments, preserves independent flags, and regenerates the same
output directory. Source verification alone does not update GN arguments.
The development configuration still omits PGO and ThinLTO. Performance evaluation
must first compare the same engine configuration in the stock and native UI hosts,
then compare a shipping configuration against a matching browser version.

The bindgen patch uses Apple's linker for Xcode SDK TAPI
compatibility. Preparation also supplies the loader-relative LLVM alias omitted
from the pinned Rust archive and retrieves DevTools' exact esbuild CIPD package.
These are build adjustments, not browser-behavior changes.

The pinned LLD 23.1.0 cannot parse the `arm64e.x1` targets in the Xcode 27
macOS SDK's `libSystem.tbd`. Use the macOS 26.5 SDK for the performance preset;
it may also be installed under Command Line Tools even when Xcode has a newer
SDK. This selects the engine SDK without changing the system Xcode selection.
The performance preset enables official-build optimizations, PGO, ThinLTO with
LLD, and profile-guided V8 builtins. It keeps debug checks disabled and preserves
Chromium's normal sandbox and accessibility behavior. This is a build
configuration, not a claim of distribution readiness or measured parity.

Retrieve the exact mac-arm profile named by `performanceInputs` in the lock from
Chromium's `chromium-optimization-profiles/pgo_profiles` Google Storage bucket
(also named in `chrome/build/mac-arm.pgo.txt`). With the build stopped, run:

```sh
python Scripts/control-plane/configure-chromium.py \
  --source /absolute/chromium/src --configuration performance \
  --sdk /absolute/MacOSX26.5.sdk --pgo-profile /absolute/pinned-profile.profdata
python Scripts/control-plane/build-chromium-baseline.py \
  --source /absolute/chromium/src --jobs 12 --min-free-gib 15
```

The configuration helper verifies the SDK version and PGO checksum before GN
generation. Check the generated compile and link commands for profile use and
ThinLTO, and the V8 snapshot command for `--turbo-profiling-input`. Changing
configuration recompiles the engine; reuse the existing output directory and
allow additional time and memory for the final ThinLTO link.

Compare stock and native hosts with the same engine, build settings, foreground
state, window size, and accessibility mode. Native accessibility inspection can
activate Chromium's full screen-reader mode and affect Speedometer scores. A
temporary `--disable-renderer-accessibility` run can isolate that measurement
cost; it must not become a product default or replace accessibility validation.
Keep diagnostic runs labeled separately from runs with normal accessibility.

With Apple's linker, the non-component development framework and V8 snapshot
generator use DWARF unwinding because this mixed C++/Objective-C/Rust build has
four personality routines, exceeding the compact format's three slots. The
framework adjustment excludes official and component builds. Keep unwind sections
and exception behavior in validation when changing this configuration; this
development workaround is not a decision about release packaging.

Do not enable component builds with the pinned prebuilt Rust standard library.
`build/rust/std/BUILD.gn` documents that its propagated linker flags can reach
components without the corresponding allocator object and leave Rust allocation
symbols unresolved. A non-component link keeps those dependencies together.

The build wrapper terminates only its own Ninja process group if free space falls
below the reserve. It does not remove source, archives, products, or shared caches.
Resume the same output directory after resolving a build failure or storage limit.

Before adding Crest hooks, validate the stock baseline with a new explicit
`--user-data-dir`. Never launch it against a production browser profile. A Crest
adapter must establish startup, helper processes, native window/page ownership,
profile isolation, input, extension behavior, and coordinated shutdown. The
presence of Chromium sources or a compiled object is not a supported engine
registration.

## Native Crest host overlay

`Overlay` contains the BrowserWindow and engine implementation. The BrowserWindow
interface adapts Mori's MIT-licensed implementation; provenance and its retained
license are in `ThirdParty`. Crest uses explicit window assignments, regular
profiles with lifetime leases, the shared core, and native-page adoption by ID.

`Patches/native-host.patch` selects that window implementation only when launched
with `--crest-control-plane`, starts the native framework without Chromium session
restoration, and routes quit through the core. The default baseline remains stock.
Validate the exact pinned inputs without changing the source:

```sh
python Scripts/control-plane/apply-chromium-host.py --source /absolute/chromium/src
```

After the baseline is validated and its build has stopped, add `--apply` to install
the overlay, regenerate GN in the same output directory, and rebuild `chrome`.
Build `CrestChromiumUI` with Xcode and embed that framework plus
`CrestCore.Native.dylib` in the browser's `Contents/Frameworks` directory. Include
the retained third-party license and sign the resulting development bundle.
`Scripts/control-plane/package-chromium-host.py` assembles an independent APFS
clone of the built browser, embeds the two libraries and license, and signs
the bundle. It requires a new output path outside `/Applications` and the
repository. A review package drops the default-browser registration.
Launch a review package with both `--crest-control-plane` and an explicit, separate
`--user-data-dir`. The host rejects startup without that explicit directory.

`--product` packages Crest's own desktop identity instead of that review
identity. It consumes the `CrestChromiumUIProduct` framework, which compiles the
same sources without `CREST_REVIEW_BUILD` and therefore uses Crest's normal
persistent store, sync and update state rather than an isolated session. The
packaged bundle takes the `com.pauldavis.crest` identifier and copies Crest's
`CFBundleURLTypes`, `CFBundleDocumentTypes`, Sparkle feed and public key from
`CrestMac/Configuration/Crest-Info.plist`, so HTTP, HTTPS and HTML registration
and `Check for Updates` work through the app's existing paths. Supply the
product identity's resolved entitlements with `--entitlements`; unexpanded build
settings are rejected. The two framework targets are alternatives and keep
separate product names, so a rebuild cannot leave one composition's resources in
the other; the packager embeds the framework it was given under its own name,
detects the composition from its `Crest-Native-Host` resource and refuses a
mismatched mode, and the host loads whichever of the two names a bundle
contains. A product bundle carries a
`Crest-Native-Host` resource instead of `Crest-Isolated-Experiment`: it hosts the
native UI for launches that carry no switches, such as Finder, the
default-browser role and Dock reopen. `--distribution` signs the product for
notarization, as described under Releasing. The packager still refuses
`/Applications` and never replaces an installed Crest.

A product bundle keeps its engine state in
`~/Library/Application Support/Crest/Chromium`, not in
`~/Library/Application Support/Chromium`, which every other Chromium on the
machine, Crest's own review and baseline packages included, also opens by
default. The browser executable resolves that directory in `main`, before the
Chromium framework is loaded and therefore before any profile is read, and
passes it as `--user-data-dir`; an explicit `--user-data-dir` on the command line
still wins. The first launch after that move adopts the `Crest-*` engine profile
directories the previous default directory still holds, and only those:
`Default` and everything else there belongs to whichever Chromium created that
directory and is left alone. Each adopted directory is named on standard error.
If the new directory cannot be created, or a profile cannot be moved, the
adoption is undone and the launch falls back to the previous directory and says
so.

Moving the directories is all that step can do: it runs before the framework is
loaded and has no JSON reader. It records what it moved, and the browser process
finishes the adoption in `ChromeMainDelegate::PreSandboxStartup`, immediately
after the user data directory is resolved and before the local-state
`PrefService` exists, let alone `ProfileManager`. Two things happen there.

First, the entries that name an adopted directory are carried out of the
previous `Local State` into the new one: its `profile.info_cache` record, its
place in `profiles_order` and `last_active_profiles`, and `last_used` when it
names one. Nothing else is copied. Without this an adopted profile is
unregistered: Crest's core restores its Spaces by path and does not read that
list, but Chromium's own profile machinery does.

Second, each adopted profile's encrypted tracked-preference validators are
retired. That covers every `protection.macs.*_encrypted_hash` entry and
`protection.super_encrypted_hash`, in `Secure Preferences` and in `Preferences`.
Those hashes are encrypted with the OSCrypt key derived from the bundle's
keychain item, and Chromium treats a stale encrypted hash as a changed
preference without consulting the legacy HMAC stored beside it: enforced tracked
preferences, `extensions.settings` among them, are reset on first launch, and
the profile loses its extensions. Removing the encrypted
validators leaves the legacy HMACs, which validate on their own and which
Chromium re-encrypts on its next write. This protects the adoption only.
Renaming a shipped Safe Storage keychain item has no such repair and must not
happen; `CrestKeychainName` carries that as a comment.

Crest mode never shows Chrome's profile picker. Startup resolves to a browser
window on the `Default` profile, and `ProfilePicker::Show` returns without
creating its window, so no route (startup, Dock reopen, a profile menu) can put
a "Welcome to Chromium profiles" window in front of the native UI.

A product bundle is launched with no switches, so the browser process declares
`--crest-control-plane` on its own command line at
`ChromeMainDelegate::BasicStartupComplete` when the bundle marker names the
native host. The Crest gates that test that switch would otherwise be dead in a
product bundle: the iCloud Passwords native-messaging fallback, declared-URL
extension updates, private profile window creation and startup profile
selection. Some of them sit in components that cannot include `//chrome`
headers.

External opens, document opens and reopen reach the native UI through
`AppController`. `crest::OpenExternalURLs` applies Crest's own external-URL
policy with Space or Quick Window routing for web links and its local-document
rules for opened files, queuing anything that arrives before the first window
exists, and `crest::Reopen` activates an existing window or
opens the initial one instead of letting Chromium create a browser with no
registered window. Normal windows are restored at startup from the list of
windows that were open at quit; their contents come from the existing per-window
state and their frames from AppKit's autosave records. Private and Quick Windows
are not restored.

An app's system sign-in (`ASWebAuthenticationSession`) reaches the host through
the same `AppController`. Chromium's handler would open a Views popup in the
last-used engine profile, which belongs to no Space, so
`crest::BeginAuthenticationSession` runs the session in a Quick Window of the
Space a link from that app routes to. A navigation throttle completes the
request when that window's page reaches the app's callback URL and then closes
the window; closing the window first cancels the request. Chromium's toasts,
which anchor to a Views frame this build never creates, become Crest notices,
and the sad-tab overlay yields to Crest's own renderer recovery.

Site state reaches Crest through the location bar Chromium already calls.
`CrestLocationBar::UpdateContentSettingsIcons` forwards to
`crest::UpdateSiteIndicators`, which relays a pop-up the engine's blocker held
back to Crest's Site Controls. Crest's per-Space permission record stays the
source of truth: each committed page applies its automatic-pop-up decision to
the engine, and allowing a blocked site opens the pop-ups the blocker kept.
Chromium's confirm info bars, such as tab sharing and `chrome.debugger`, have no Views
container here, so each page observes its `ContentInfoBarManager` and Crest
shows the bars in the page with the engine's own button labels.

The native UI uses the named isolated session `chromium-native-ui-review` by
default. Set `CREST_ISOLATED_PERSISTENCE_ID` to a different name and provide a
separate `--user-data-dir` for an independent session, including benchmark runs.
Use the Release configuration of `CrestChromiumUI` for performance comparisons.

The host keeps Chromium's process and application lifecycle. The Swift framework
contains no application entry point. `CrestChromiumUI` compiles Crest's existing
shared and macOS UI, and `CrestChromiumRoot` mounts `BrowserMacApplication` in
native windows. `ChromiumNativePage` supplies the WebContents view inside the
existing page card.

The pinned toolbar row belongs to the Space rather than to a page. Its actions
come from the Space's own profile, so a Space showing its Start Page still shows
the extensions pinned to it. The open page's per-tab state, such as its badge
and dynamic icon, is overlaid when there is one. Clicking a pinned action without a page open
opens that action's popup against the Space's browser directly: there is no tab
to activate, grant host access for or inject into, so an action that has no
popup of its own, including any page action, reports itself unavailable instead.
A private window reads the same pinned list narrowed to the extensions enabled
in incognito.

The row prepares the Space's engine profile itself, so the tiles are there on
the first Start Page of a launch rather than only once something has been opened
in the Space. Which Spaces it may prepare is decided by `(spaceID, profileID)`
against the store family that owns the window it is drawn in, not by identity
against one application-wide list: a window publishes its own Spaces first, and
the list would still be empty at that point. A Space belonging to another family,
such as a borrowed settings workspace or a private window with no persistent
engine profile of its own, is refused, and so is a locked Space. The preparation is
idempotent, so it can be asked on every appearance and every Space change.

An extension that is still enabled in the registry but whose directory is gone
is treated as unavailable rather than broken: it contributes no tile and no
settings row, and its action declines to run, so a click states Crest's own
unavailable notice instead of navigating the popup to Chromium's
ERR_FILE_NOT_FOUND page. The check is one stat per extension per registry
change.

Action popups are hosted in a borderless Crest window, not in an `NSPopover`.
On macOS 27 the popover composites a translucent system material with whatever
it hosts, which tints the extension's own rendering, and no opaque layer behind
the web contents removes it without hiding the renderer. The popup window is
borderless, becomes key so the extension's own fields can be typed into, and is
a child of the Crest window it was opened from. Its content view is a plain
layer-backed container with no vibrancy and nothing opaque between it and the
renderer. It carries the same 12pt rounded corners as Crest's controls, with the
extension's view as its only subview. It has no arrow, because a popover's
arrow is filled with the popover's own background colour, and Crest does not
know the colour an extension's document paints. The anchor logic places it
below the control it was opened from, flipping above and sliding along the
screen at an edge, and Chromium's auto-resize keeps following the document. It
dismisses on a click outside, on Escape, when its window moves, resizes or
minimises, when Crest goes to the background, and when the extension closes
its popup, is unloaded or has its host destroyed.

Crest reuses its original extension artwork, badge, pinning, toolbar tiles,
Site Controls grid, and Space-selection list. `Apple/Extensions/Presentation`
contains those engine-independent views; `ChromiumExtensionStore` supplies
profile-scoped Chromium state and native install presentation. Registry, action,
toolbar, and icon observers refresh the UI without polling. Pinning is stored in
Chromium's per-profile toolbar preferences.

On a Chrome Web Store listing, the listing's own install button reads **Add to
Crest** and runs Crest's install; **Install Extension…** in Site Controls does
the same thing from the toolbar. Both download
the CRX3 package from Google's update service. Chromium verifies the publisher
proof and expected ID before Crest shows the original install review layout.
The review displays Chromium's permission warnings and offers website-access
withholding where supported. Required API permissions use Chromium's install
consent semantics rather than the retired WebKit permission emulation.
Selected additional Spaces install the same downloaded package, each with its own
signature check and separate extension data. Consent is reused only when the
verified extension identity, version, and warnings match. Locked, deleted, or
replaced Space profiles cannot receive a copy.

The native Extensions settings pane retains Space selection, extension artwork,
disclosure rows, enable/remove controls, options pages, and copying to other
Spaces. Chromium's manager is available for detailed permissions, developer-mode
unpacked installs, and engine-specific controls. The store's own Add to Chrome
button is inert in the ungoogled baseline, so Crest takes it over: a script in
an isolated world, injected only into `chromewebstore.google.com` documents in a
regular profile, relabels that button **Add to Crest**, **Added to Crest** or
**Remove from Crest** from Chromium's own registry and routes a click into the
same install review. The click is delivered as a request in the listing's own
URL fragment, and the host installs only the extension the listing's address
names, so a store page cannot name another one. The same script releases the
store's desktop minimum width, which is wider than a Crest page card and would
otherwise push the listing and its button past the card's edge, and hides the
store's prompts to switch to Chrome. Crest mode also restores
Chromium's declared-URL extension update requests; signature and permission
checks remain owned by Chromium.

Companion apps such as Apple's Passwords helper and 1Password register their
native-messaging hosts for Google Chrome and do not know Crest's directories. In
Crest mode only, when the regular Chromium lookup finds no manifest, the host
checks Chrome's per-user `NativeMessagingHosts` directory and then its global
one. Chromium still validates the manifest and the extension IDs it allows, so a
host answers only the extensions its app registered, and Apple's helper still
controls authentication and access to the password vault. Crest does not
copy Chrome's profile, change Apple's helper, or read passwords itself.
Apple's signed helper also checks the parent browser's identity. A browser needs
an Apple-approved identity or the managed
`com.apple.developer.web-browser.public-key-credential` entitlement with a
matching provisioning profile. Crest's production App ID has that capability;
the separate experimental bundle needs its own Apple approval. Merely adding the
entitlement to an experimental signature does not make it authorized.

Passkeys use the macOS system sheet, as they do in the WebKit engine. Chromium's
iCloud Keychain authenticator is only discovered when the browser holds
`com.apple.developer.web-browser.public-key-credential` and the request carries
the NSWindow the sheet is presented from. Chromium finds that window through a
`views::Widget`, which Crest windows do not have, so in Crest mode the window the
page contents actually live in is used instead. With the authenticator available,
Crest skips Chromium's own mechanism sheet and sends both `get()` and `create()`
straight to the system, which performs Touch ID or iCloud Keychain and offers its
own nearby-device, QR and security-key fallbacks. Cancelling the system sheet
returns to Chromium's mechanism list once, so the engine's phone, USB and
security-key flows stay reachable. Creation defaults to iCloud Keychain rather
than a browser-owned store, and Chromium's staged rollout features for that
choice do not apply. A build without the entitlement, such as the review package, keeps
Chromium's own sheet, so passkeys there are not a test of Crest's behaviour.

Private windows use separate off-the-record profiles, and extension actions are
filtered by Chromium's incognito authorization.

A browsing window the engine creates for itself, such as one from
`chrome.windows.create` or an extension app window, routes to a Crest window. Crest reserves the window when
the Browser is created, maps its profile to a Space, and opens the window when
the Browser's first tab is offered for adoption; a renderer popup still joins
its opener's window instead. An off-the-record profile maps only to the private
window, and a profile with no Space to host it is declined rather than routed
into an unrelated Space. `focused: false` opens the window without making it
key; a requested window `state` is ignored. A request no Space can host is refused
before its window is created, so `chrome.windows.create` reports an error
instead of leaving its promise unsettled. Picture-in-picture keeps its Views window, which Chromium drives on
its own, and so does a DevTools frontend the user has undocked.

A docked DevTools frontend is mounted inside the Crest page card it inspects.
This build never creates Chrome's Views contents container, so the
`DevtoolsUIController` that normally decides whether docking is possible and
lays the frontend out does not exist. Crest answers in its place for a
WebContents one of its pages owns, and applies the frontend's own
`DevToolsContentsResizingStrategy`, which carries the dock side, splitter
position and drawer height, to the card interior. The frontend's undock button
still works and Chromium then opens the window the user asked for; re-docking
returns it to the card.

Extension side panels are hosted as a card in the page row beside the page they
belong to, not as a tab, and are neither persisted nor synced. Crest resolves
the panel through `extensions::SidePanelService` and
`ExtensionViewHostFactory::CreateSidePanelHost`; Chrome's own
`SidePanelCoordinator`, reader and reading-list panels stay off. The extension
action's context menu, `chrome.sidePanel.open()`, `chrome.sidePanel.close()` and
the action's open-on-icon-click behavior all reach that card. Chromium's own
open and close helpers, which otherwise drive the Views side-panel UI this build
never creates, hand the request to the card belonging to the tab it names; a
window-wide request belongs to that window's active tab. A repeated request for
the panel already on screen closes it on an icon click and is ignored by the
API. `setOptions` that retracts an entry, and an extension that unloads, close
the card they were showing.

An extension's `chrome.commands` bindings are matched in the host after Crest's
own shortcuts have had the key equivalent: a named command is delivered as
`commands.onCommand` with the active-tab grant Chromium requires, and an
`_execute_action` binding runs the action through Crest's own button path,
anchoring its popup to the extension's pinned tile or, when it has none, to the
control that opens the window's extension list. The
bindings themselves belong to the engine; the Extensions settings pane links to
Chromium's own shortcut page for changing them.

Packaged experiments require `--signing-identity` with a stable Apple Development
or Developer ID identity. Ad-hoc signing changes the keychain trust identity on
rebuilds and is rejected. A keychain item's access list trusts the signatures
that created it, and a profile directory does not namespace it, so every Crest
bundle takes a Safe Storage item of its own keyed on its bundle ID: `Crest Safe
Storage` for `com.pauldavis.crest`, `Crest Review Safe Storage` for the review
package, `Crest Chromium Baseline Safe Storage` for the baseline. A Crest bundle
never falls through to Chromium's shared `Chromium Safe Storage` item, whose
access list is what made macOS ask for the login password when a differently
signed Crest build opened it. Changing a bundle's Safe Storage name rotates its
encryption key: cookies and passwords written under the previous name do not
decrypt, and Chromium rewrites that state on the next launch. Keep the same
signing identity and bundle identifier across rebuilds. Encryption remains
backed by the macOS keychain.

A packaged experiment refuses startup without an explicit absolute
`--user-data-dir`, and a review native-host package also requires
`--crest-control-plane`. A product package names its own directory instead.
This guard runs before Chromium loads its framework or opens any profile. The
host restores its core-managed Spaces directly, without Chrome's profile picker.

## Releasing

The engine, Chromium with this host's patch and overlay compiled in, cannot
be built on a hosted runner, so releases download a prebuilt engine.
`Scripts/control-plane/chromium_engine.py` names it by a key over every engine
input: the source lock, the host patch and its input hashes, the overlay, the
host header and the scripts that prepare, configure and build it. After
changing any of them, apply the host, build, and publish from the build Mac:

```
python3 Scripts/control-plane/publish-chromium-engine.py \
  --source <chromium src> --ninja <chromium-tools>/bin/ninja
```

It refuses to publish unless the checkout holds this branch's patch output and
overlay and the build has nothing left to do, then uploads the zipped
`Chromium.app` once as the `chromium-engine-<key>` prerelease. The experimental
release workflow downloads the engine matching its branch, builds the native
core and `CrestChromiumUIProduct`, and packages the product with
`package-chromium-host.py --product --distribution`: every executable, library
and bundle is signed innermost first with the hardened runtime and a secure
timestamp, the renderer and GPU helpers keep Chromium's JIT entitlement, and
the app receives Crest's resolved entitlements, taken from the notarized
WebKit export built in the same run, over Chromium's device entitlements. The
workflow then notarizes the app and its disk image. The Chromium build is the default download on `appcast-experimental.xml`; the
WebKit build is published beside it as an alternate on
`appcast-experimental-webkit.xml`, and each follows only its own feed.

