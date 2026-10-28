# CrestShared/Features/Onboarding

First-run setup and launch recovery. `BrowserOnboardingPages` is the protocol
each platform implements, one page per core `SetupStep`; manual setup is a
wizard over a setup draft the core holds until the host applies it.
`BrowserSessionRecoveryView` shows when the saved session cannot be opened.

## Goal

A setup flow the core drives, so a step the core adds fails to compile until
every platform says what it shows there.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserOnboardingPages.swift`, `SetupStep+OnboardingPages.swift` | The per-step page protocol and the step-to-page mapping |
| `BrowserSessionRecoveryView.swift` | Session recovery: restore a checkpoint or retry |
| `BrowserManualSetupView/` | The Space setup wizard, its model and the sidebar preview |
| `Components/` | Onboarding panel modifier, primary and secondary button styles |
| `Support/` | Onboarding palette, typography, panel view extension, setup look preview |

## Depends on

The core's setup contract (`SetupStep`) through
`CrestShared/Infrastructure/Core/`, `CrestShared/Application/BrowserOnboarding/`,
`Spaces/` and `Tabs/`. Implemented by `CrestMac/Features/Onboarding/` and
`CrestMobile/Features/Onboarding/`; recovery is shown by
`CrestMac/App/Shell/BrowserMacLaunchRecovery.swift` and
`CrestMobile/App/CrestMobileApp.swift`.

## Rules

- Setup state lives in the core; the host's final action applies it (`BrowserManualSetupView/Components/BrowserSpaceSetupWizard.swift`).
- Forced-onboarding and setup launches use `CREST_ISOLATED_SESSION=1` (`Documentation/RepositoryGuardrails.md`, "Isolated validation sessions").
- A new `SetupStep` needs a page on every platform; the protocol makes that a compile error (`BrowserOnboardingPages.swift`).

## Read next

`CrestShared/Application/BrowserOnboarding/`, then the platform
`Onboarding/` folder.
