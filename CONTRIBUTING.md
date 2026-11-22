# Contributing to Crest

Crest is licensed under the Mozilla Public License 2.0. Contributions are
accepted under the same license. The Crest name and visual identity remain
covered by [`TRADEMARKS.md`](TRADEMARKS.md).

## Who can contribute code

Anyone can have one pull request open at a time. Vetted contributors can have
more open at once. To become one, message Paul on
[Discord](https://discord.gg/gjrM5qMB6x) so you can talk it through first.
The basic requirements:

- You are a developer with some background building software.
- You understand C# and SwiftUI.
- You may use AI tools, but not to cover for experience you don't have. You
  must be able to explain every line you submit.

Approval is at the maintainer's discretion and can be revoked at any time.
The maintainer reviews every pull request, including one from a vetted
contributor, before it merges. Pull requests from contributors who aren't
vetted are reviewed as time allows.

Everyone is welcome to report bugs in GitHub Issues and to discuss ideas on
r/CrestBrowser and Discord.

## Local setup

1. Install Xcode with SDKs supporting the macOS 15.0 and iOS 26.1 deployment targets.
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen).
3. Install the .NET SDK pinned by `CrestCore/global.json`, for example with
   `Scripts/control-plane/install-dotnet.sh`.
4. Use Python 3.11 or later for the Chromium and release tools. Check that
   `python3 --version` resolves to that interpreter.
5. Install [ripgrep](https://github.com/BurntSushi/ripgrep) for the script
   test suite, and Node.js 20 or later if you build the Help Center in
   `HelpCenter/`. `swift-format` ships with Xcode; the checks call it through
   `xcrun`.
6. Run `Scripts/bootstrap.sh` from the repository root.

Building the `Crest` scheme produces the WebKit composition of the Mac app. The
published Mac app also packages a prebuilt Chromium engine; see
[`CrestEngines/Chromium/README.md`](CrestEngines/Chromium/README.md) before
changing engine inputs.

`project.yml` is authoritative. Do not hand-edit target membership or build settings only in Xcode, because the next project generation will replace those changes.

## Validation

Run `Scripts/validate-identity.sh` after product metadata or persistent identifier changes. Run `Scripts/validate-cache-hygiene.sh` after building or testing, and run `Scripts/validate.sh` for the macOS and iOS unit gates. The validation script reuses one temporary Derived Data directory and removes it on success, failure, or interruption.

For repository-only changes, run `Scripts/check-architecture.py` and
`Scripts/check-swift-format.sh`; use `--base main` to include committed branch
changes in the formatting check.
`Scripts/audit-periphery.sh` repeats the dead-code evidence audit across every
app scheme and configuration when Periphery is installed. Its output never
justifies deletion without reference, build, and test proof. See
[`Documentation/RepositoryGuardrails.md`](Documentation/RepositoryGuardrails.md)
for the enforced contracts and current exact exemptions.

**Build Crest** runs on pull requests and pushes to `main`, and can also be
dispatched manually. It checks source, core tests and analyzers, architecture,
scripts, Swift formatting, native contracts, macOS and iOS builds, and the Help
Center. The macOS and iOS builds run once per change: a draft pull request
waits until it is marked ready for review, and the push to `main` that merges
a pull request runs only the checks, since the branch was already built. A
direct push to `main` builds everything. Release publication calls the same
workflow's checks for the exact source SHA and waits for them to pass, then
builds the Mac product while signing it. Run the relevant local validation
before opening a pull request; builds do not replace native app acceptance
checks.

Run `Scripts/audit-licenses.py` whenever a package, website dependency, copied
source file, font, or other third-party asset changes. New runtime dependencies
must have a redistributable license and a preserved notice before they land.

Mac builds are universal: arm64 and x86_64, built on Apple silicon. New Mac targets, destinations, and scripts build both.

## Community and planning

Use [r/CrestBrowser](https://www.reddit.com/r/CrestBrowser) to discuss early
ideas, user questions, and compatibility experiences before they become
actionable engineering work. Use GitHub Issues for reproducible bugs and
concrete outcomes. The public
[Crest Roadmap project](https://github.com/orgs/crest-browser/projects/1) and
release milestones summarize planned work. Only the maintainer adds items to
them: opening an issue or a pull request doesn't put it on the roadmap or
commit to building it. [The roadmap](Documentation/ROADMAP.md)
is generated from public GitHub issues with `Scripts/render-roadmap.py --write`.
The renderer updates only its marked section, preserving the platform notes.

See [SUPPORT.md](SUPPORT.md) for reporting routes and
[GOVERNANCE.md](GOVERNANCE.md) for the current ownership and decision model.

## Change discipline

- Keep SwiftUI presentation native and adaptive.
- Preserve exact Space isolation for website data, credentials, history, tabs, settings, and synchronization.
- Cover important behavioral contracts with focused regression tests. Review visual appearance, layout, and animation in the running app.
- Keep build products, diagnostic captures, audit reports, submission packets, user state, credentials, signing exports, and local environment files out of Git. Documentation should help public users and contributors; keep private planning and machine-specific instructions local.
- Do not add task-specific Markdown results or closeout reports, including under Documentation, or upload them as release or issue attachments. Summarize validation in the task or issue discussion. Keep necessary local evidence outside the checkout; maintained docs should describe lasting behavior and instructions, not dated test totals or cleanup narratives.
- Keep personal editor and coding-assistant state local. The tracked exceptions are the root `AGENTS.md` and the `crest-contribution` skill; `Scripts/check-public-source.py` rejects everything else.
- Do not enable the managed iOS default-browser entitlement until Apple approves it for the Crest App ID.

## AI-assisted contributions

You may use AI tools. Any change an AI tool helped produce must follow the
[`crest-contribution` skill](.agents/skills/crest-contribution/SKILL.md),
which carries the code style, architecture, UI, test, verification and
writing rules a reviewer will hold the change to. Claude Code discovers it
through `.claude/skills/crest-contribution`, Codex through `.agents/skills`,
and every other agent is pointed to it by [`AGENTS.md`](AGENTS.md). Load it
before the agent changes anything and keep it loaded while it works.

The pull request template has an AI usage section with two boxes: that AI
tools helped, and that the skill was run and its output reviewed. The
**Contribution checks** workflow fails a pull request that ticks the first
without the second, or that removed the section. You remain responsible for
understanding, validating and explaining everything you submit.

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

Every user-visible or architecture-significant work commit adds its release
notes to the file for the version it moves to,
`Documentation/ReleaseNotes/<major>.<minor>/<version>.json`, which
`Scripts/set-version.sh` names after the bump. Each entry has a unique lowercase
kebab-case `id`, a `category` and a `message`. Choose `new`, `improved`, or
`fixed` for public notes and write the message as a concise user-facing outcome.
Use `internal` to record architecture, release, or tooling work that should not
appear to users. Add `"platforms": ["mac"]` or `"platforms": ["ios"]` when a
change reaches only that platform. An entry never changes once it is on `main`.
The fix-commit check requires the new staged entries, in that version's file,
alongside the patch bump.

Keep commits focused and use a Conventional Commit subject such as
`refactor(settings): adopt native split navigation`. Commit subjects remain
useful development history, but release copy comes from the release notes. The
release commit of a Stable version adds that version's curated write-up as
`release` in its file, and receives an annotated `vX.Y.Z` tag; an App Store
release receives an `ios-vX.Y.Z` tag. Do not invent historical release tags.

## Developer Certificate of Origin

Crest uses the [Developer Certificate of Origin 1.1](https://developercertificate.org/).
Sign off each commit with `git commit -s` to certify that you have the right to
submit the contribution under this project's license. The sign-off is a commit
trailer, not a transfer of copyright:

```text
Signed-off-by: Your Name <you@example.com>
```

The **Contribution checks** workflow fails a pull request when any of its
commits lacks the trailer. Merge commits are skipped, and pull requests
opened by bots or by the repository owner are exempt.
