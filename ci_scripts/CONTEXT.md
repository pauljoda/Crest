# ci_scripts

The Xcode Cloud hooks, found by Xcode Cloud at this fixed path. They guard
the manual archive workflow: what may start it, which scheme and Xcode it
uses, and that the archived app carries the repository's version and the
build number Xcode Cloud assigned. Outside Xcode Cloud each exits at once.

## Goal

Refuse any archive that is not a manual, release-Xcode build of the
expected scheme and version.

## Contents

| File | What it is |
| --- | --- |
| `ci_post_clone.sh` | Requires a manual archive, the platform's scheme, a release Xcode, the expected repository and commit, the pinned project format and deployment targets; runs `Scripts/check-version.sh --static` and installs .NET |
| `ci_pre_xcodebuild.sh` | Writes Xcode Cloud's build number into the project and checks the Release version and build resolve as expected |
| `ci_post_xcodebuild.sh` | Checks the archived app's bundle identifier, version and build before distribution |

## Depends on

`Config/Version.xcconfig`, `project.yml`, `Scripts/check-version.sh`,
`Scripts/control-plane/install-dotnet.sh`. Contracts checked by
`Scripts/Tests/test_xcode_cloud_configuration.py`.

## Rules

- Xcode Cloud owns distributed build numbers; never change `CURRENT_PROJECT_VERSION` in the repository (`Documentation/RepositoryGuardrails.md`, "Fix commit versions").
- Mac releases ship through GitHub Releases (and the Homebrew cask) with Sparkle updates, iPhone and iPad through TestFlight and the App Store (`Documentation/Distribution.md`, introduction).

## Read next

`Documentation/Distribution.md` and `Scripts/Tests/test_xcode_cloud_configuration.py`.
