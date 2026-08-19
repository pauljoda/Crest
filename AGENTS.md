# Crest Repository Instructions

## Versioning completed work

- Every committed app-code change must advance `MARKETING_VERSION` with `Scripts/set-version.sh --patch` unless the commit explicitly opens a new release line.
- Keep routine development versions on the current `0.4.x` line until the user explicitly requests a release-line change.
- Do not increment `CURRENT_PROJECT_VERSION`; Xcode Cloud owns distributed build numbers.
- Before committing app-code changes, stage `Config/Version.xcconfig` with the task-owned files and run `Scripts/check-version.sh --fix-commit`.
