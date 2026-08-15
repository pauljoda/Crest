# Repository guardrails

Crest keeps repository checks narrow enough to express real architecture contracts. They intentionally do not guess whether a number is a design token or whether a declaration reported by static analysis is safe to delete. Visual ownership is explicit: meaningful SwiftUI types require direct, deterministic previews under the vertical feature contract.

## Changed-file formatting

The root `.swift-format` configuration preserves Crest's four-space indentation and 120-column style. Check current staged, unstaged, and untracked Swift changes without rewriting them:

```sh
Scripts/check-swift-format.sh
```

For a branch or pull request, include every Swift file changed since a known base:

```sh
Scripts/check-swift-format.sh --base main
```

The script only invokes strict `swift-format lint`. It never runs formatter write mode and never performs a repository-wide formatting pass.

## Architecture and Xcode 27 compatibility

Run:

```sh
Scripts/check-architecture.py
```

The check enforces these high-confidence contracts:

- Domain imports Foundation only; Application imports Foundation, Observation, and Dispatch only.
- SwiftUI presentation stays out of shared Infrastructure.
- AppKit, CoreServices, and SecurityInterface stay under `CrestMac`; UIKit stays under `CrestMobile`.
- Production code does not introduce `ObservableObject`, `@Published`, or `AnyView`.
- Conservative checks cover the documented Xcode 27 `@State` initialization and composition hazards, nested `TupleView` constraints, empty MapKit builders, and modified shape styles passed to non-builder `background` or `overlay` forms.

The Xcode 27 patterns follow Apple's [TN3211](https://developer.apple.com/documentation/technotes/tn3211-resolving-swiftui-source-incompatibilities-for-state-and-contentbuilder). They supplement compiler validation; they do not attempt to parse every legal Swift expression.

`Config/ArchitectureGuardrails.json` is the machine-readable exception register. Every entry is exact and carries a reason. All WebExtension feature, Application, Infrastructure, and platform-adapter paths are enrolled; none are hidden behind a path exclusion. Current migration debt is limited to one existing Quick Window material expression that is already compiling under Xcode 27 and needs visual validation before changing.

An exemption is not precedent for another file: add new debt only with a focused review and a written reason, and prefer removing entries as ownership improves.

## Vertical feature organization

Run:

```sh
Scripts/check-vertical-structure.py
```

The guard applies Crest's vertical organization contract across `CrestShared`, `CrestMac`, and `CrestMobile`:

- Organize feature code under `Features/<Feature>`, with `Components`, `Models`, `Services`, and `Support` only where the feature needs them.

- Feature roots contain screen entry views; direct `Components` files are visual, while direct `Models`, `Services`, and `Support` files are nonvisual.
- Every Swift file contains exactly one file-scope declaration per Swift file. Each primary enum, struct, class, actor, protocol, or type alias has a matching filename, while an extension lives alone in a matching `Type+Concern.swift` file even when it extends that file's former primary owner. File-scope functions, operators, and stored values do not share a file with another declaration. Named conformance extensions use the declared protocol in the suffix and contain no unrelated globals.
- A view file contains its single view declaration, with secondary views in dedicated component files.
- Root screens compose real, narrowly scoped `View` types. Root-screen `body` implementations plus computed `some View` and `@ViewBuilder` sections over the focused line limit become real component boundaries.
- Every meaningful SwiftUI visual type directly renders itself in a deterministic `#Preview` beside the component.
- Previews reject known live persistence, network, Keychain, filesystem, WebKit-store, default-web-view, asynchronous remote-image, and production-composition dependencies across both the macro and rendered component implementation. Preview identity and dates are fixed. A previewed View cannot own `@AppStorage`; persisted preferences belong in an injected model or store so the preview consumes ordinary in-memory state.

`Config/VerticalStructureDebt.json` is an exact, sorted ledger for the remaining 0.3.0 reorganization. It is deliberately not a broad path exclusion: every entry identifies one rule, source path, and subject. A new key fails the guard, and resolving an owner leaves a stale key that must be removed in that same focused commit. This makes the contract immediately enforceable while the existing feature-by-feature debt is reduced to zero.

Substantial components may own nested component families plus their own `Components`, `Models`, `Services`, and `Support`. Direct files in a component family remain visual; nonvisual state and support move into the matching nested bucket. Named screen families use the same four buckets, while arbitrary peer folders are rejected.

Share content, policies, and behavior across platforms while keeping macOS and mobile shells, framework delegates, and system adapters explicit in their platform roots.

## Isolated validation sessions

Every fixture, forced-onboarding, setup, showcase, credential test, SwiftUI Preview, or automated app launch must use Crest's isolated launch graph. Set `CREST_ISOLATED_SESSION=1` for validation launches even when another fixture flag already implies isolation.

Never run sample Spaces against the installed profile. A normal installed-app launch without isolation is reserved for an explicit release handoff and must not include fixture flags.

## Focused guard tests

The general architecture and vertical checks above are the supported
repository-wide gates. Their focused regression tests, plus version and product
site coverage, run with Xcode's bundled Python:

```sh
python3 -m unittest \
  Scripts.Tests.test_repository_guardrails \
  Scripts.Tests.test_direct_distribution_contract \
  Scripts.Tests.test_public_source_contract \
  Scripts.Tests.test_vertical_feature_contract \
  Scripts.Tests.test_version_contract \
  Scripts.Tests.test_product_site
```

`Scripts/check-public-source.py` separately inspects the exact Git index and
rejects coding-assistant instructions or state, machine-local editor files,
local environment configuration, and Apple signing or provisioning material.
Ignored local worktrees do not enter the public snapshot, while an accidental
forced add fails CI.

Feature-specific structural tests under `Scripts/Tests` document narrower
ownership migrations. Run the relevant module when changing one of those
features; they are not an aggregate repository-wide gate.

The supported guards follow the same dependency direction as production code. Framework-neutral default-browser and passkey values and policies stay in Domain, their observable workflow controllers stay in Application, and AuthenticationServices, AppKit, UIKit, and Security bridges stay in shared or platform Infrastructure. Launch flags are parsed by `BrowserLaunchEnvironment`, evaluated by the Application launch policy, and read from the process only by the Infrastructure adapter; BrowserStore composition consumes that typed value.

Structural assertions check current owners and reject superseded paths. Keep those checks recursive where they protect a layer or framework boundary, and match declarations or signatures flexibly enough to allow formatting and typed parameters without accepting a different contract. The Python tooling itself must remain compatible with the Python 3.9 runtime bundled with Xcode.

WebExtension compatibility, access, and permission values and pure policies live in Domain; runtime summaries remain Application projections; localized copy lives in Presentation; Safari discovery stays under `CrestMac`; and native-messaging capability detection stays in each platform Infrastructure root. The recursive neutrality and ownership checks cover these paths without exclusions.

## Periphery evidence audit

Install [Periphery](https://github.com/peripheryapp/periphery) when running the optional dead-code audit:

```sh
brew install periphery
Scripts/audit-periphery.sh
```

The script scans both app schemes across Debug and Release using one task-scoped Derived Data directory, then removes that directory. It retains Objective-C-accessible declarations and Codable properties up front. Its remaining findings are evidence only. Before deleting anything, prove references and target membership, run the affected builds and tests, and account for dynamic WebKit, AppKit, delegate, serialization, and preview entry points.
