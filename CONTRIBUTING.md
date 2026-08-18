# Contributing to Crest

Crest is licensed under the Mozilla Public License 2.0. Contributions are
accepted under the same license. The Crest name and visual identity remain
covered by [`TRADEMARKS.md`](TRADEMARKS.md).

## Local setup

1. Install Xcode 27 or another Xcode containing the macOS 26 and iOS 26 SDKs.
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen).
3. Run `Scripts/bootstrap.sh` from the repository root.

`project.yml` is authoritative. Do not hand-edit target membership or build settings only in Xcode, because the next project generation will replace those changes.

## Validation

Run `Scripts/validate-identity.sh` after product metadata or persistent identifier changes. Run `Scripts/validate-cache-hygiene.sh` before handing work back, and run `Scripts/validate.sh` for the macOS and iOS unit gates. The validation script reuses one temporary Derived Data directory and removes it on success, failure, or interruption.

For repository-only changes, run `Scripts/check-architecture.py`,
`Scripts/check-vertical-structure.py`, and `Scripts/check-swift-format.sh`; use
`--base main` to include committed branch changes in the formatting check. The
vertical check uses an exact debt ledger: structural refactors remove their
resolved entries in the same commit, while new violations are rejected.
`Scripts/audit-periphery.sh` repeats the dead-code evidence audit across every
app scheme and configuration when Periphery is installed. Its output never
justifies deletion without reference, build, and test proof. See
[`Documentation/RepositoryGuardrails.md`](Documentation/RepositoryGuardrails.md)
for the enforced contracts and current exact exemptions.

Run `Scripts/audit-licenses.py` whenever a package, website dependency, copied
source file, font, or other third-party asset changes. New runtime dependencies
must have a redistributable license and a preserved notice before they land.

The project supports Apple silicon only. Keep new targets, destinations, and scripts arm64-native.

## Community and planning

Use [r/CrestBrowser](https://www.reddit.com/r/CrestBrowser) to discuss early
ideas, user questions, and compatibility experiences before they become
actionable engineering work. Use GitHub Issues for reproducible bugs and
concrete outcomes. The public
[Crest Roadmap project](https://github.com/users/pauljoda/projects/3) and
release milestones summarize planned work without exposing private planning
details. The one-way mapping is documented in
[`Documentation/PlanningSync.md`](Documentation/PlanningSync.md).

See [SUPPORT.md](SUPPORT.md) for reporting routes and
[GOVERNANCE.md](GOVERNANCE.md) for the current ownership and decision model.

## Change discipline

- Keep SwiftUI presentation native and adaptive.
- Preserve exact Space isolation for website data, credentials, history, tabs, settings, and synchronization.
- Add a failing regression test before implementing behavior changes.
- Keep generated output, user state, credentials, signing exports, and local environment files out of Git.
- Keep editor and coding-assistant instructions or state local; `Scripts/check-public-source.py` rejects them from the tracked tree.
- Do not enable the managed iOS default-browser entitlement until Apple approves it for the Crest App ID.

## Versions, changelog, and commits

`Config/Version.xcconfig` is the only source for Crest's public version. Versions
use complete `X.Y.Z` semantic versioning. Once a fix is verified and ready to
commit, run `Scripts/set-version.sh --patch`, stage the version file with the
fix, and run `Scripts/check-version.sh --fix-commit`. Each independently
verified fix advances the patch component once; when several already verified
fixes intentionally share one commit, use `Scripts/set-version.sh --patch N` to
account for all of them.

Changing the major or minor release line is a separate release decision. Use
`Scripts/set-version.sh --release X.Y.Z` only when that release and its tag have
been explicitly approved. Xcode Cloud continues to own distributed integer
build numbers while the repository keeps build `1` as its local fallback.

Every user-visible or architecture-significant work commit updates the
`Unreleased` section of `CHANGELOG.md` in plain language. Keep commits focused
and use a Conventional Commit subject such as `refactor(settings): adopt native
split navigation`. A fix commit includes its patch bump and changelog entry in
that same commit. Release commits freeze `Unreleased` under an ISO date and
receive an annotated `vX.Y.Z` tag. Do not invent historical release tags.

## Developer Certificate of Origin

Crest uses the [Developer Certificate of Origin 1.1](https://developercertificate.org/).
Sign off each commit with `git commit -s` to certify that you have the right to
submit the contribution under this project's license. The sign-off is a commit
trailer, not a transfer of copyright:

```text
Signed-off-by: Your Name <you@example.com>
```
