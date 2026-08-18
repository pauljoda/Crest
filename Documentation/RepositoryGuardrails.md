# Repository guardrails

Crest keeps repository checks narrow enough to express real architecture contracts. They intentionally do not guess whether a number is a design token, whether a declaration reported by static analysis is safe to delete, or how many declarations and folders a cohesive feature needs.

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

## Fix commit versions

Every verified fix advances the patch component of Crest's public version in
the same commit:

```sh
Scripts/set-version.sh --patch
git add Config/Version.xcconfig
Scripts/check-version.sh --fix-commit
```

Pass a positive count to `--patch` only when one focused commit intentionally
contains that many independently verified fixes. The fix-commit check reads the
Git index and rejects a missing, unstaged, non-increasing, or major/minor bump.
Changing release lines uses `Scripts/set-version.sh --release X.Y.Z` and remains
an explicit release-and-tag decision. Neither path changes
`CURRENT_PROJECT_VERSION`; Xcode Cloud owns distributed build numbers.

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

The guard applies Crest's deliberately small organization contract across `CrestShared`, `CrestMac`, and `CrestMobile`:

- Organize code by user-visible feature or runtime capability. Folder names describe the behavior a developer is looking for; `Components`, `Models`, `Services`, and `Support` are available vocabulary, not mandatory layers.
- A file holds one cohesive concept. Name it for either its primary owner or the role of a tightly related group; small single-use values, private helpers, related global declarations, and nested types should live with that concept. Multiple extensions may share a file when they extend that same owner. Use `// MARK:` sections named for the behavior they contain, rather than generic labels such as `Utilities` or `Animation`.
- Split a type only at a boundary that improves comprehension: a meaningful subview, a distinct lifecycle, a protocol conformance with real platform value, a large independently testable policy, or a cross-target/framework constraint. File count and line count are evidence, not goals; roughly 100–400 lines is a comfortable range and larger cohesive owners are acceptable.
- A protocol needs at least two production implementations or a genuine system boundary that cannot run in tests, previews, or the current process. Prefer a concrete store configured with disposable dependencies over paired production/in-memory protocols whose only second conformer is a test double.
- Root screens compose meaningful, narrowly scoped `View` types. Large root `body` implementations and large computed view builders remain guarded, but small owner-scoped subviews and values may stay in the same file.
- Add previews for meaningful screens and reusable visual states, not mechanically for every leaf. The curated hosts are the macOS and mobile browser roots, sidebars, representative tab rows, settings and onboarding roots, Quick Window, Site Settings, software updates, command palette, extensions, credential detail, navigation failure, manual setup, Space branding, and utility content. Leaf changes are viewed through those integration surfaces. Any preview that exists must remain deterministic and reject known live persistence, network, Keychain, filesystem, WebKit-store, default-web-view, asynchronous remote-image, and production-composition dependencies. Preview identities and dates are fixed, and previewed views do not own live `@AppStorage` state.

`Config/VerticalStructureDebt.json` remains the exact ledger for the few machine-enforced rules. It is currently empty. A new violation must be fixed or recorded with a focused reason; resolving one removes the stale entry in the same change.

Tests lock behavior whose regression would break a user workflow, persistence or migration contract, security boundary, data transformation, platform integration, or other costly invariant. Do not add tests merely to pin localization copy, design-token values, accessibility identifier strings, previews, file paths, declaration placement, or a mechanical refactor. Repository scripts may keep a small focused suite for their durable failure modes.

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

Do not add feature-specific source-topology tests. The repository-wide guards
own framework and dependency direction; feature behavior belongs in focused
Swift tests or direct app validation.

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
