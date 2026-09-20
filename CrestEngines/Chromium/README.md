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
