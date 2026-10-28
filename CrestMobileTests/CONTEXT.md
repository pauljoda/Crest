# CrestMobileTests

The iOS Swift test target, hosted by the `CrestMobile` app. It keeps only
what the mobile adapters do differently: scene and root models, navigation,
the Space pager, sidebar reordering, drag sources, shared links, transient
browsing, page configuration and system password isolation.

## Goal

Cover mobile-only behavior without repeating the shared contracts that
`CrestTests/` already owns.

## Contents

| Path | What it is |
| --- | --- |
| `Mobile*Tests.swift` | Mobile adapter contracts: root and window scene models, navigation, interop, pager, reorder policy, transient browsing |
| `Browser*Tests.swift` | Shared link parsing, drag sources, system password write-through isolation |
| `BrowserStore+Unlocking.swift` | Test-only Space unlocking for the store |
| `Support/` | `MobileBrowserPageStore+Presenting.swift`, page presentation for tests |

## Depends on

The `CrestMobile` target (`TEST_HOST`) and `CrestContracts/include`. Run by
`Scripts/validate.sh` through the `CrestMobile` scheme.

## Rules

- Preserve separate platform coverage only where the adapters behave differently (`AGENTS.md`, "Test retention and cleanup").
- Default to no new test, and never test appearance (skill, "Tests").
- Test launches use `CREST_ISOLATED_SESSION=1` (`Documentation/RepositoryGuardrails.md`, "Isolated validation sessions").

## Read next

`CrestMobile/CONTEXT.md`, then `CrestTests/CONTEXT.md` to check the contract
is not already covered there.
