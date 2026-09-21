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
the development bundle. It requires a new output path outside `/Applications`
and the repository, and removes default-browser registration from that copy.
It does not notarize or publish a distributable release.
Launch with both `--crest-control-plane` and an explicit, separate
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
native UI for launches that carry no switches — Finder, the default-browser role,
Dock reopen — and uses Chromium's default profile directory for its own bundle
identity. Signing and provisioning that identity for distribution remain
external requirements; the packager still refuses `/Applications` and never
replaces an installed Crest.

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
The native UI uses the named isolated session `chromium-native-ui-review` by
default. Set `CREST_ISOLATED_PERSISTENCE_ID` to a different name and provide a
separate `--user-data-dir` for an independent session, including benchmark runs.
Use the Release configuration of `CrestChromiumUI` for performance comparisons.

The host keeps Chromium's process and application lifecycle. The Swift framework
contains no application entry point. `CrestChromiumUI` compiles Crest's existing
shared and macOS UI, and `CrestChromiumRoot` mounts `BrowserMacApplication` in
native windows. `ChromiumNativePage` supplies the WebContents view inside the
existing page card. Complete capability validation and distributable packaging
remain part of the integration work.

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

Apple installs its iCloud Passwords native-messaging manifest in Chrome's system
directory. In Crest mode only, the host checks that location specifically for
`com.apple.passwordmanager` when the regular Chromium lookup finds no manifest.
Chromium still validates the manifest's allowed extension IDs, and Apple's helper
still controls authentication and access to the password vault. Crest does not
copy Chrome's profile, change Apple's helper, or read passwords itself.
Apple's signed helper also checks the parent browser's identity. A browser needs
an Apple-approved identity or the managed
`com.apple.developer.web-browser.public-key-credential` entitlement with a
matching provisioning profile. Crest's production App ID has that capability;
the separate experimental bundle needs its own Apple approval. Merely adding the
entitlement to an experimental signature does not make it authorized.

Private windows use separate off-the-record profiles, and extension actions are
filtered by Chromium's incognito authorization.

A browsing window the engine creates for itself — `chrome.windows.create`, an
extension app window — routes to a Crest window. Crest reserves the window when
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
lays the frontend out does not exist; Crest answers in its place for a
WebContents one of its pages owns, and applies the frontend's own
`DevToolsContentsResizingStrategy` — which carries the dock side, splitter
position and drawer height — to the card interior. The frontend's undock button
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
rebuilds and is rejected. The host and baseline use separate Crest-named Safe
Storage entries; neither requests Chromium's shared keychain item. Keep the same
signing identity and bundle identifier across rebuilds. Encryption remains
backed by the macOS keychain.

The packaged executable refuses startup without an explicit absolute
`--user-data-dir`. A native-host package also requires `--crest-control-plane`.
This guard runs before Chromium loads its framework or opens any profile. The
host restores its core-managed Spaces directly, without Chrome's profile picker.
