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

## Versioning completed work

- A change never edits `Config/Version.xcconfig`. It names the release line's
  base version, and each build's patch version is derived from history:
  `Scripts/derive-version.py version` prints what a commit builds as.
- Only a maintainer-requested release line moves the base, with
  `Scripts/set-version.sh --release X.Y.0` in a commit of its own, checked by
  `Scripts/check-version.sh --release-commit`.
- Do not increment `CURRENT_PROJECT_VERSION`; the release pipeline owns
  distributed build numbers.
- Before committing app-code changes, stage the task-owned files with the
  change's release-note entry and run `Scripts/check-version.sh --fix-commit`.

## Explicit release notes

- Every committed app-code or architecture-significant change adds its own
  entry file, `Documentation/ReleaseNotes/<id>.json`, in the same commit:
  `{"category": "...", "message": "..."}`. Never edit
  `Documentation/ReleaseNotes.json`; it is frozen, and release builds assemble
  it with the entry files in the order history added them.
- Use a unique lowercase kebab-case ID, as the file name, and one of `new`,
  `improved`, `fixed`, or `internal`. Use `internal` only when the change
  should not appear in public release notes.
- Write public entry messages as concise user-facing outcomes rather than
  commit subjects, implementation details, issue IDs, or test descriptions.
- Never reuse, rename, edit, or delete an existing entry or entry file.

## Generated localization catalog

- Whenever `CrestShared/Resources/Localizable.xcstrings` changes, treat the
  regenerated catalog as task-owned output and include it with the current
  work instead of leaving it as unrelated worktree noise.

## Published Chromium engine

- The release workflow cannot build Chromium; it downloads a prebuilt engine
  named by the key `Scripts/control-plane/chromium_engine.py` computes over
  its inputs: `CrestEngines/Chromium/source.lock.json`, `host-inputs.json`,
  `Patches/`, `Overlay/`, `Apple/CrestChromiumHost.h`, and the prepare, apply,
  configure, and build scripts in `Scripts/control-plane/`.
- Any change to those inputs needs a new engine published by a maintainer, as
  described under "Releasing" in `CrestEngines/Chromium/README.md`. A branch
  whose key has no published `chromium-engine-<key>` release fails its next
  release. State in the pull request that the change touches engine inputs so
  the publish is planned with the merge.
- Swift, native core, and packaging changes reuse the published engine and
  need no new one.

## Test retention and cleanup

- Never create, commit, or upload task-specific validation or results
  Markdown, security findings or audit reports, benchmark logs, screenshots,
  or closeout packets in this repository, including `Documentation/`. Put
  concise evidence in the pull request; keep necessary local artifacts outside
  the checkout.
- Documentation is for maintained product behavior and contributor
  instructions, not dated test totals, machine paths, investigation
  transcripts, or cleanup narratives. `ReleaseNotes.json` and the generated
  roadmap remain supported public records.
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
