# CrestNative

Native Apple composition files for the apps that embed the core library.
Today it holds only entitlements for the native-core targets and their
provisioned CloudKit review builds.

## Goal

Keep signing inputs for the core-hosting targets out of the shared Swift tree.

## Contents

| Path | What it is |
| --- | --- |
| `Apple/Composition/ControlPlane.entitlements` | Default entitlements of the `CrestNativeCore` target (`CREST_NATIVE_CORE_ENTITLEMENTS` in `project.yml`) |
| `Apple/Composition/MacCloudReview.entitlements` | Entitlements for a provisioned macOS CloudKit review build |
| `Apple/Composition/MobileCloudReview.entitlements` | Device entitlements of `CrestMobileNativeCore` |

## Depends on

No source imports it. `project.yml` references `ControlPlane.entitlements` and
`MobileCloudReview.entitlements`; `MacCloudReview.entitlements` is passed at
build time through `CREST_NATIVE_CORE_ENTITLEMENTS`
(`Documentation/Architecture/ControlPlane.md`, "Isolated CloudKit review").

## Rules

- Targets and their settings live in `project.yml`; never set them only in Xcode (`CONTRIBUTING.md`, "Local setup").
- Review builds use an isolated session and their own cloud ID (`Documentation/Architecture/ControlPlane.md`, "Isolated CloudKit review").
- No signing or provisioning material is committed (`Documentation/RepositoryGuardrails.md`, "Focused guard tests"; enforced by `Scripts/check-public-source.py`).

## Read next

`Documentation/Architecture/ControlPlane.md` ("Isolated CloudKit review",
"Build workflow").
