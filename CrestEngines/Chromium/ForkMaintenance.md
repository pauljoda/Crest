# Maintaining Crest's Chromium fork

The fork is the pinned recipe and patch set in Crest. `~/Dev/CrestChromium` is its
durable build workspace. A separate Git repository is unnecessary while the
Chromium host and Crest's C ABI evolve together. No product code belongs only in
the expanded Chromium tree: make changes in the overlay or patch set first.

## Build workspace

Install Python 3.11 or newer, Go, Xcode and its Metal toolchain. Retain the macOS
SDK named by `performanceInputs.macSDKVersion` in `source.lock.json`. Use one
tools environment and one source/output directory per pinned upstream recipe:

```sh
python3 -m venv ~/Dev/CrestChromium/tools
~/Dev/CrestChromium/tools/bin/python -m pip install ninja==1.13.0
export PATH="$HOME/Dev/CrestChromium/tools/bin:/opt/homebrew/bin:$PATH"
python Scripts/control-plane/chromium-fork.py status
python Scripts/control-plane/chromium-fork.py build \
  --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

The command verifies upstream pins, prepares missing source, applies Crest's
host, configures the performance build, compiles, and checks JavaScript execution
in a headless browser with a temporary profile. It does not use installed Crest
or personal browser state. This smoke check covers engine startup and rendering;
native window, Space, input, extension, and persistence acceptance remains part
of approving the Chromium product for stable distribution.

The workspace contains `sources/<preparation-key>/src`, a `downloads` cache,
`profiles`, `tools`, and the Actions runner. App and ABI updates reuse the same
upstream build. Changing the upstream recipe gets a new directory and preserves
the previous working engine. Before an update prepares its source, it removes
every other prepared source except the one its checkout builds from, so the
workspace holds at most the integration branch's source and one update's.
Preparation requires 50 GiB free; compilation keeps a 15 GiB reserve. These are
minimum gates, not a maximum disk budget. Inspect incomplete preparations,
including a `src.partial` directory, before resuming them. Remove other obsolete
source directories only when no process uses them and the previous working
engine is published.

To adopt an existing prepared source/build directory on the same volume:

```sh
python Scripts/control-plane/chromium-fork.py adopt --source /path/to/chromium/src
```

Adoption verifies the source version, Crest's build patches and the installed
host before moving it, and leaves a compatibility symlink at the previous path.
Subsequent builds reuse the managed workspace. Run maintenance through the
workspace command, which locks out other managed operations. Stop older direct
Ninja commands before changing the shared source; those commands predate the
workspace lock.

## Source and toolchains

The engine is plain Chromium from Google's official source archive,
`chromium-<version>-lite.tar.xz`, whose SHA-256 the lock pins from the published
manifest. Preparation applies no third-party patch set, prunes nothing and
substitutes no domains.

The archive is exported on Linux and carries none of the Mac toolchains. Its own
`DEPS` pins each Google Storage object Chromium's build fetches, with a SHA-256,
so preparation evaluates `DEPS` for an Apple Silicon host and fetches only the
dependencies the lock lists: Chromium's clang and Rust toolchains, the Mac
libclang, and Node. Those are the compilers Chrome itself is built with. `DEPS`
names the build's Python, esbuild and the TypeScript compiler only by CIPD
version tag, so the lock pins each package's instance digest; an update resolves
new digests from the new archive's `DEPS`. Downloads are cached in `downloads`
by digest.

`crestPatches` in the lock are build adjustments applied at preparation: DWARF
unwinding for the development preset's Apple-linked framework and V8 snapshot
generator. The performance preset links with LLD and does not use them.

## Upstream updates

Crest follows the upstream Stable channel for Mac; `fork.json` names the channel
and the chromiumdash feed it is read from. A new milestone ships about every two
weeks, with security fixes on the current one in between, so updating is routine
work. Every update starts with
a plan that changes nothing:

```sh
python Scripts/control-plane/chromium-fork.py check-upstream
python Scripts/control-plane/chromium-fork.py plan --version 157.0.8103.80
```

`check-upstream` names the newest release on the pinned milestone and the newest
milestone, each with what Google's release notes say about it: how many security
fixes it carries, how many are Critical or High, whether one fixes a vulnerability
exploited in the wild, and whether it is an early stable release, which reaches a
small share of people about a week before everyone. A release with no note of its
own, such as a respin that changes only the version, reports the note of the
latest release it covers. The source archive appears a few hours after a release;
until then a plan reports that it isn't published yet. Use a real version reported
by `check-upstream`; the one above illustrates the syntax.

`plan` downloads the release's archive and PGO profile into the workspace cache,
reads the pinned and new archives, and writes its report to `reports/<version>` in
the workspace: `plan.json`, the candidate `source.lock.json`, the patches as they
would carry over, and any conflicts. It decides:

- **The path.** A release that keeps the milestone, every toolchain its `DEPS`
  fetches and every tool the lock pins *advances* the built tree in place: only
  the files the release changed are rewritten, and Ninja recompiles what depends
  on them. Anything else needs a *fresh* source directory and 50 GiB free.
- **Whether the PGO profile rolled.** The profile is part of every compile
  command, so a new one recompiles the whole engine on either path.
- **How each Crest patch carries over**, in series order: *unchanged*; *applies*
  (the file changed upstream and the patch still applies forward without fuzz);
  *rebased* (Crest's change merged cleanly onto the new file, and the rebased
  patch is in the report); *upstream* (the release already makes Crest's change,
  so the report's patch drops that section); *conflict* (the merge, with diff3
  markers, is in the report's `conflicts`); or *missing* (the release no longer
  has the file).
- **Whether the build adjustments** in the lock's `crestPatches` still apply to
  the release's files. Preparation and an advance both apply them without fuzz.
- **Pure virtual methods** added or removed in the upstream headers the overlay
  includes: where the host implements or calls one of them, it must change.
- **Helper apps** in `chrome/installer/mac/signing/parts.py` that
  `ENGINE_HELPER_KINDS` in `chromium_engine.py` doesn't know. Packaging and
  publishing refuse an unknown helper, so give each the entitlements `parts.py`
  gives it.
- **Network traffic annotations** added or removed, for the request review
  below.

Then build it from a clean Crest checkout:

```sh
python Scripts/control-plane/chromium-fork.py update --version 157.0.8103.80 \
  --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

`update` runs the plan and stops if any patch is rebased, already upstream,
conflicting or missing, or a build adjustment no longer applies: review the
report's patches, commit the ones you accept to `Patches/`, and plan again. A
patch already rebased for the release counts as applying. Once every patch
applies, `update` pins the archive checksum, the CIPD tools and the PGO profile,
advances or prepares the source, refreshes the host hashes, and builds and
smoke-checks the engine. It restores the source lock and host hashes if anything
fails before the build. Before compiling, the build checks that every overlay
source compiles to an object file: Chromium sometimes folds the target the
host's sources sit in into another one, and a list GN accepts can still compile
nothing. `last-build.json` in the workspace records the path, whether the
profile rolled and how long each step took. Only a source that a build installed
Crest's host in is advanced; any other prepares fresh. An advance that stops
partway leaves `advancing.json` in its source, and builds and updates refuse
that source until it has been inspected. A build failure leaves the candidate in
place: fix it and run `chromium-fork.py build`.

Advancing moves the shared tree to the update, so other engine builds wait until
the update merges. If the update is abandoned instead, the next build for the
pinned release prepares a fresh source.

A new Chromium may add helper apps, and distribution packaging runs the signed
package's own helpers and refuses one that can't load a page, because an unsigned
build passes everything a hardened signature can break. That check runs the
engine without Crest's interface, so before publishing an engine, also load real
pages, an extension and a sign-in in Crest packaged with `--distribution`, in an
isolated copy (`CREST_ISOLATED_SESSION=1`).

### Deciding what ships

| Release | Steps | Ships |
| --- | --- | --- |
| A fix on the pinned milestone | `plan`, `update`, open the PR while the `--distribution` package is tested | Development once a maintainer publishes the engine and merges, then stable with the next release |
| A fix for a vulnerability exploited in the wild | The same, at once: other engine work in the workspace waits | Stable the same day, once Development is checked |
| A toolchain change on the pinned milestone | `update` prepares a fresh source | As a fix |
| A new milestone | Days ahead, `plan --allow-major` against its early stable release; rebase the patches it reports and review its requests. Once it is stable, `update --allow-major` | When its PR is reviewed and merged |

A milestone prepares its source beside the pinned one. Once its engine is
published and its PR merged, run `chromium-fork.py prune` from the merged
checkout: it removes every source except the one that checkout builds from, and
the cached archives and PGO profiles that source doesn't use. Pruning refuses to
run while any Chromium build is running, including one started without the
workspace lock.

## Crest's patches

`Patches/series` lists the patches applied over the overlay, in order. A file
may appear in more than one; each later patch applies to the earlier ones'
result, and `host-inputs.json` records each file's hash before the first and
after the last. Every patch states its reason in its header.

| Patch | What it does |
| --- | --- |
| `native-host.patch` | Crest's native window, pages, engine binding and the integrations the README describes. |
| `google-request-allowlist.patch` | Hooks the network service so the browser's own requests reach Google only for the services below. |
| `component-updater-services.patch` | Registers only the CRLSet, PKI metadata (Certificate Transparency logs, pins and Chrome Root Store), and file types for download warnings. |
| `update-pings-off.patch` | Removes the active-day and roll-call counters from component and extension update checks, and the install and update event pings. |
| `autofill-crowdsourcing-off.patch` | Autofill sends no form signatures or field votes to content-autofill.googleapis.com. |
| `gaia-list-accounts-off.patch` | The browser never sends google.com cookies to `/ListAccounts` on a cookie change. |
| `network-time-off.patch` | No time queries to Google. |
| `intranet-redirect-detector-off.patch` | Never starts the intranet redirect detector, whose probes of random hostnames served only the omnibox. |
| `web-push-off.patch` | `PushManager.subscribe()` fails at once instead of registering with Google's GCM, which issues a persistent device identity. |
| `privacy-defaults.patch` | Starting values: Related Website Sets off, Safe Browsing off, `<a ping>` off, no network prediction, no alternate error pages or search suggestions, no Chromium password, address or card saving, no `canMakePayment`, and WebRTC limited to the default route's public address. Third-party cookies keep Chromium's default: allowed, and blocked in private windows. Chromium applies that block only to its primary incognito profile, and each Crest private window has its own off-the-record profile, so the patch treats every off-the-record profile as incognito for cookie controls. |
| `safe-browsing-reports-off.patch` | Whatever the Safe Browsing setting, no download pings, extended reporting, enhanced protection, client-side phishing reports or SCT auditing. |
| `certificate-transparency-enforced.patch` | Enforces Certificate Transparency, which Chromium does only in Google Chrome builds. |
| `manifest-v2-extensions.patch` | Keeps Manifest V2 extensions loading, without deprecation warnings. |
| `content-filter.patch` | Puts each Crest page's requests through the core's content filter, which blocks ads and trackers from the enabled filter lists, wires Chromium's `js_injection` renderer component in so each page runs the filter's scriptlets as its documents start, and gives Crest's content bridge user style sheets for its hiding rules, which the page can't read or override. |

`network-time-off`, `intranet-redirect-detector-off`, most of
`privacy-defaults`, `certificate-transparency-enforced` and
`manifest-v2-extensions` are adapted from ungoogled-chromium, whose BSD-3-Clause
license is retained in the repository's `ThirdParty/Chromium-LICENSE.txt`. The defaults keep the
values Crest's earlier ungoogled engine had, so a person's settings don't change.

Already off in a Chromium build, and checked again at each milestone: metrics
and crash upload (no consent, no UI), the variations seed (fetched only with
`--variations-server-url`), domain reliability (needs metrics consent), RLZ
(Chrome only), sign-in and sync (no OAuth client), the Optimization Guide and
on-device AI (no consent, no components), translation (Crest translates pages
itself), the Privacy Sandbox ad APIs, and the hangout services extension.

## Browser requests to Google

`Overlay/services/network/crest_request_policy.cc` decides each request in the
network service, redirects included. A request is allowed when its host isn't
Google's, when a renderer made it (a page, worker or extension), or when its
traffic annotation is one a page or the person directs: a navigation, a
download, a worker script, developer tools, and the network's own certificate,
DNS and proxy work. Otherwise a request to Google needs a service entry naming
its annotation and host, and fails with `ERR_BLOCKED_BY_CLIENT` without one.
The list fails closed: a request a later Chromium adds is blocked until it is
reviewed.

The services are the component updater (`update_client`) for
update.googleapis.com and its download hosts, extension update checks and
packages (`extension_manifest_fetcher`, `extension_crx_fetcher`,
`content_hash_verification_job`) for clients2.google.com and its download
hosts, and Crest's own Web Store download (`crest_web_store_download`).

Review the list at every milestone update:

1. Compare `tools/traffic_annotation/summary/annotations.xml` in the new source
   with the pinned one. List the IDs added and removed.
2. Read each added annotation's `semantics` in its source file: who sends it,
   when, what data, and its `destination`.
3. An annotation for a request a page or the person directs joins `kDirected`.
   One for a Google service Crest needs joins `kServices` with the hosts it
   uses, and its reason in the comment beside it. Leave every other one out,
   which blocks it.
4. Remove entries for annotations Chromium removed.
5. In the review build, capture a NetLog over startup, ten idle minutes, a
   Chrome Web Store install, an extension update check and a few page loads.
   Every host the browser contacted outside page loads must be on the list, and
   the log must show no other request to a Google host.

## Certificate trust

The component updater keeps the CRLSet, the Certificate Transparency log list
and the Chrome Root Store current. Until the first update arrives, the engine
uses the blocklist, root store and log list compiled into its source. Chromium
stops enforcing Certificate Transparency 70 days after the built-in log list's
date, which the component update replaces.

`native-host.patch` carries upstream distrust changes the pinned source does not
yet contain, copied hunk for hunk from Chromium:

| Files | Change | Upstream |
| --- | --- | --- |
| `net/data/ssl/chrome_root_store/root_store.textproto`, `root_store.certs` | Removes emSign ECC Root CA - G3 | Chrome Root Store version 43, Chromium `8793082f793c` |

The root store keeps its pinned version number. Once an upstream release
contains a change, its hunks no longer apply and the update stops there: remove
those sections from the host patch and refresh the host inputs.

## Safe Browsing

Safe Browsing is compiled in and off. Its list updates need a Google API key,
which Crest doesn't have, and the request list blocks every Safe Browsing host.
Download checks, extended reporting, enhanced protection's real-time lookups,
client-side phishing reports and SCT auditing send page, download or
certificate details to Google; `safe-browsing-reports-off.patch` turns them off
in code, whatever the setting, and the request list blocks them too. Turning
Safe Browsing on later takes a key and service entries for the list-update
annotations (`safe_browsing_v4_update` or `safe_browsing_v5_update`) only.

## Protected video

Chromium is built without Widevine (`enable_widevine = false`), and the
component updater doesn't fetch Google's module. Most video services require
Widevine's verified media path, which only Google Chrome's signature carries,
so Chromium's own module failed inside the page instead of letting it move. A
page that asks for Widevine or PlayReady now moves to WebKit, which plays
FairPlay, through `ProtectedMediaUnavailable`, unless the person chose an
engine for the site. The core's `ProtectedMediaService` names Netflix,
Disney+, Max and Prime Video, whose sites open in WebKit from the start.

## GitHub Actions

Install the repository-scoped runner on the build Mac:

```sh
python Scripts/control-plane/install-chromium-runner.py
```

This verifies GitHub's runner archive checksum and installs a user LaunchAgent
with the `crest-chromium` label. It starts at login; the Mac must remain awake and
online to accept builds. Use `~/Dev/CrestChromium/runner/svc.sh stop` and `start`
from that directory to control it. Signing keys stay in the existing release
environment. The maintenance workflow has no pull-request trigger; never run
untrusted pull-request code on this persistent personal Mac.

Configure these repository variables:

| Variable | Purpose |
| --- | --- |
| `CHROMIUM_WORKSPACE` | Absolute persistent workspace path on the Mac |
| `CHROMIUM_SDK` | Absolute path to the SDK pinned by the source lock |
| `CHROMIUM_BUILD_JOBS` | Compiler parallelism, default 8 |
| `CHROMIUM_CI_ENABLED` | `true` allows manual and scheduled engine builds |
| `CHROMIUM_UPSTREAM_ENABLED` | `true` builds new fixes on the pinned milestone every six hours and opens a draft PR for each |

The workflow must be present on the default branch for its schedule to run. Its
`fork.json` integration branch must also contain the maintenance scripts. Use the
Actions UI or `gh workflow run chromium.yml --ref <workflow-branch> -f operation=check`
to check upstream. `operation=build` builds and publishes the pinned engine;
`operation=update` builds a released update and opens it as a draft PR.
`upstream_version` can select a specific release, and `allow_major=true` allows
a milestone. The repository must allow Actions to create pull requests.

An update PR contains the new pins, host hashes, a patch version increment, a
release-note entry, and the plan's summary. Its engine is built in the workspace
and not published: a maintainer tests it, publishes it with
`publish-chromium-engine.py` and then merges. A release run that finds no engine
for its commit builds one on the Mac, so publish before merging. App release jobs
consume only the artifact whose engine key matches their own source. No signing
job reads a mutable local build directory.

## Publishing experimental builds

Enable `CHROMIUM_CI_ENABLED=true` after registering the Mac, then publish the
experimental branch with its own workflow definition:

```sh
gh workflow run experimental-release.yml --ref chromium-control-plane \
  -f source_ref=chromium-control-plane
```

The release resolves the branch to one commit. The reusable `Ensure Chromium
engine` workflow checks for its published engine, including the full input key,
archive, and checksum. If missing, it builds and publishes that engine on the
Mac. An existing artifact skips the Mac entirely. The signing job then downloads
that engine, verifies its checksum, builds Crest's native core and UI from the
same commit, and signs and notarizes the installer. It publishes the
experimental feed and its `-webkit` twin, which offers the same installer.

## Scheduled upstream updates

Keep `CHROMIUM_UPSTREAM_ENABLED=false` during initial setup; manual updates can
still build a candidate for review. The six-hour schedule runs from `chromium.yml`
on the default branch, checks the integration branch named in `fork.json`, and
reports the newest release with its release-note summary. Turning the variable on
lets it build a new fix on the pinned milestone and open a draft PR with the plan,
the release notes and how long each step took. While a session or another engine
build holds the workspace lock or runs Ninja, a run leaves a notice and the next
check tries again. A release gets one PR, and a closed PR stays closed; while one
is open, the schedule waits for it. A new milestone is only reported, because its
patches and requests need a review.

Nothing the schedule builds is published or merged without a maintainer. Turn
`CHROMIUM_UPSTREAM_ENABLED=false` to stop scheduled builds, or
`CHROMIUM_CI_ENABLED=false` to stop all engine builds, and cancel a running
workflow to stop it at once. A failed or conflicting update keeps the previous
appcast in service. To roll back an engine, restore its reviewed pins in a new
patch-version commit and publish a newer app build; do not replace an existing
engine artifact or decrease the Sparkle build number.
