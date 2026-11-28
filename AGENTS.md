# Crest repository instructions

These instructions apply to every coding agent working in this repository.
They hold on any machine and contain nothing private.

## Load the contribution skill first

Before changing source, tests, documentation or pull request text, load the
`crest-contribution` skill at `.agents/skills/crest-contribution/SKILL.md`
(Claude Code finds the same skill through `.claude/skills/crest-contribution`).
It carries the C# and Swift style, the architecture, UI and test rules, and
the pull request requirements. Every AI-assisted pull request must follow it,
and the pull request template asks the author to confirm that it did.

`CONTRIBUTING.md` and `Documentation/RepositoryGuardrails.md` remain the base
contract for setup, validation and change discipline.

Someone who isn't a vetted contributor can have only one pull request open
at a time (see "Who can contribute code" in `CONTRIBUTING.md`). Keep their
work in that one pull request.

## Addresses leaving Crest

Every address Crest hands to another app (copying, sharing, Markdown,
dragging) goes through Super Copy: Swift passes a `BrowserCopiedLink` that
only the core's `LinkToCopy` makes, and new trackers are `$removeparam` rules
in the core, never Swift code. The contribution skill's Architecture section
has the details.

## Versions come from git

- Pull requests never change the version. `Config/Version.xcconfig` holds the
  release line's anchor version and changes only when a maintainer opens a
  new line with `Scripts/set-version.sh --release X.Y.Z`.
- Every commit on `main` takes its version from git: the anchor plus the
  commits on main's first-parent history since it, as
  `Scripts/crest_version.py` computes. Pull requests therefore merge in any
  order without re-bumping.
- Do not change `CURRENT_PROJECT_VERSION`; the release pipeline owns
  distributed build numbers.

## Explicit release notes

- A pull request that changes app code adds one new fragment,
  `Documentation/ReleaseNotes/changes/<slug>.json`, holding its entries as
  `{"entries": [...]}`. The entries belong to the version of the commit that
  merges the pull request; one with several fixes lists one entry for each.
  Add `"platforms"` listing `mac`, `ios`, `windows` or `linux` when a change
  reaches only those platforms. An entry without `platforms` reaches every
  platform, the desktop shell for Windows and Linux included, so a change only
  the Apple apps receive lists `["mac", "ios"]`.
- Use a unique lowercase kebab-case ID and one of `new`, `improved`, `fixed`,
  or `internal`. Use `internal` only when the change should not appear in
  public release notes.
- Write public entry messages as concise user-facing outcomes rather than
  commit subjects, implementation details, issue IDs, or test descriptions.
- When a change includes a community contribution, from a pull request's
  author or co-author, end its public entry, and its line in the release
  write-up, with `Thanks to <Name> (@<GitHub login>).`
- Never reuse, change, move, or delete an existing entry, whether it is in a
  fragment or in the per-version files under
  `Documentation/ReleaseNotes/<major>.<minor>/`, which are history. The
  **Version and release notes** check enforces these rules on every pull
  request; after committing, run it locally with
  `python3 Scripts/release_note_catalog.py --pull-request origin/main`.

## Generated localization catalog

- Whenever `CrestShared/Resources/Localizable.xcstrings` changes, treat the
  regenerated catalog as task-owned output and include it with the current
  work instead of leaving it as unrelated worktree noise.

## Published Chromium engine

- The release workflows cannot build Chromium; each downloads a prebuilt
  engine for its host, named by the key `Scripts/control-plane/chromium_engine.py`
  computes over that host's inputs. Every host shares
  `CrestEngines/Chromium/source.lock.json`, `host-inputs.json`, `Patches/`,
  `Overlay/`, the engine contract headers, and the prepare, apply, configure,
  and build scripts in `Scripts/control-plane/`. Each host adds its own: the
  Mac's `Apple/CrestChromiumHost.h`, and Windows' `Hosts/win-x64.json` with the
  layers it names under `Layers/` (`Desktop`, the desktop shell, and
  `Windows`).
- Keep code where only the hosts that compile it read it. Desktop shell
  sources and patches go in `Layers/Desktop`, Windows-only ones in
  `Layers/Windows`, never in the shared `Overlay/` or `Patches/`, so a desktop
  change needs only the Windows engine and the Mac's stays valid. A change to
  a shared input needs every host's engine.
- Any change to a host's inputs needs that host's engine published by a
  maintainer, as described under "Releasing" in
  `CrestEngines/Chromium/README.md`. A branch whose key has no published
  engine fails that host's next release. State in the pull request which
  hosts' engine inputs the change touches so the publishes are planned with
  the merge.
- Swift, native core, and packaging changes reuse the published engine and
  need no new one.
- The core links a prebuilt content filter the same way:
  `CrestCore/native/ContentFilter/artifact.lock.json` names it, and a change to
  that crate or its build recipe needs a maintainer to publish a new
  `content-filter-<key>` release, as its README describes. Say so in the pull
  request too.

## Test retention and cleanup

- Never create, commit, or upload task-specific validation or results
  Markdown, security findings or audit reports, benchmark logs, screenshots,
  or closeout packets in this repository, including `Documentation/`. Put
  concise evidence in the pull request; keep necessary local artifacts outside
  the checkout.
- Documentation is for maintained product behavior and contributor
  instructions, not dated test totals, machine paths, investigation
  transcripts, or cleanup narratives. `Documentation/ReleaseNotes` and the
  generated roadmap remain supported public records.
- Keep the permanent suite focused on important, durable contracts: shared
  browsing and state behavior, persistence and migration, privacy and
  authorization boundaries, extension compatibility and recovery, and measured
  performance limits.
- Visual appearance, layout, animation, styling, and static UI copy are
  covered by manual product review. Do not add or retain permanent tests
  solely for those details. Retain UI-driven tests when their assertions
  protect browsing state, Space or window ownership, privacy, native input
  routing, accessibility semantics, or another durable behavioral contract.
- Temporary tests, probes, fixtures, and diagnostic harnesses may be used
  while reproducing an issue, developing a fix, or validating an experiment.
  Before handing off completed work, remove those temporary artifacts and any
  obsolete or redundant tests made unnecessary by the final implementation.
- Retain a regression test from a bug fix only when it protects an important
  behavior that is not adequately covered elsewhere. Its origin in a bug fix,
  age, or filename alone is not a reason to keep or delete it.
- Prefer one focused behavioral test at the owning layer over duplicated
  platform cases, source-text assertions, file-layout checks, trivial wrapper
  tests, or tests that mirror implementation details. Preserve separate
  platform coverage when adapters have distinct behavior.
- Before removing a permanent test, identify the contract it covered and the
  stronger retained coverage, or explain why that contract is obsolete. Do not
  delete a failing test merely to obtain a green run; resolve whether the
  product contract or the expectation changed.
- During cleanup, consolidate overlapping fixtures and cases rather than
  adding a new test framework. Run the affected retained tests and report what
  was removed, what protection remains, and any remaining validation gaps.
