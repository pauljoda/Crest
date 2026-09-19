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
precompiled headers. The bindgen patch uses Apple's linker for Xcode SDK TAPI
compatibility. Preparation also supplies the loader-relative LLVM alias omitted
from the pinned Rust archive and retrieves DevTools' exact esbuild CIPD package.
These are build adjustments, not browser-behavior changes.

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

The host keeps Chromium's process and application lifecycle. The Swift framework
contains no application entry point. Its current UI is the migration UI;
production UI cutover, complete capability validation and distributable packaging
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
