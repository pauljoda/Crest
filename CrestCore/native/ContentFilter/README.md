# Content filter

Crest's content filter is [adblock-rust](https://github.com/brave/adblock-rust),
Brave's MPL-2.0 ad-block engine, behind the C interface in
`include/crest_content_filter.h`. The core links it statically on every Apple
platform; `CrestCore/src/CrestCore/Application/ContentBlocking` holds the
managed side. It compiles EasyList-, uBlock Origin- and AdGuard-style filter
lists into one filter, checks requests against it, describes what a page hides,
and converts lists into WebKit content rules.

## How builds get it

A Mac build of Crest needs Rust only when the crate's sources differ from the
published lock. `artifact.lock.json` names a prebuilt archive of the three
static libraries (macOS, iOS and the iOS Simulator) and the header, with the
digest of the archive and of every file in it. The core's builds run
`Scripts/control-plane/fetch-content-filter.py`, which downloads the archive
from the `content-filter-<key>` release once, checks it against the lock and
keeps it under `CrestCore/artifacts/content-filter`. The core's tests load a
dynamic library linked from the verified macOS static library; on Linux, where
no prebuilt library runs, they compile the crate, which needs Rust.

If the archive is not published yet and Rust is installed, the library is
compiled from source instead and must match the lock's digest. When the crate's
sources no longer match the lock, as while changing them, a checkout with Rust
compiles them and one without refuses. `CREST_CONTENT_FILTER_FROM_SOURCE=1`
always compiles.

## Changing it

The key, which `Scripts/control-plane/content_filter.py key` prints, hashes the
crate, its `Cargo.lock`, the pinned `rust-toolchain.toml` and the build recipe
in `content_filter.py`. Any change to them needs a new archive:

1. Install [rustup](https://rustup.rs); the crate pins its toolchain.
2. Run `python3 Scripts/control-plane/content_filter.py build`. It builds every
   library with paths remapped, so the result does not depend on the machine's
   folders, packages them and rewrites the lock.
3. When `Cargo.lock` changed, run `content_filter.py notices` and update
   `contentFilterCrates` in `Config/ThirdPartyDependencies.json`; the license
   audit compares both with the lock.
4. Commit the lock with the change and say in the pull request that the content
   filter changed.

The `Content filter` workflow rebuilds every library from source on a Mac and
compares each with the lock, and on `main` requires the archive to be published.

## Releasing

A maintainer publishes the archive for the change before it merges:

```sh
python3 Scripts/control-plane/content_filter.py build
python3 Scripts/control-plane/publish-content-filter.py --dry-run
python3 Scripts/control-plane/publish-content-filter.py
```

Publishing refuses unless the sources hash to the lock's key and the archive
matches the lock's digest, and never replaces a release that is already
published. Check it with
`gh release view "$(python3 Scripts/control-plane/content_filter.py tag)"`.
