# CrestTests

The macOS Swift test target, hosted by the `Crest` app. It covers the
contracts that break silently: session authority and recovery, persistence
and sync codecs, Space access and privacy, credentials and Keychain, downloads
risk, navigation and link policy, page pools, native input routing and the
agent bridge. A listed subset also runs as `CrestNativeCoreTests` against the
`CrestNativeCore` app.

## Goal

One focused behavioral test per durable contract, at the layer that owns it.

## Contents

| Path | What it is |
| --- | --- |
| `Browser*Tests.swift` | Tests by contract, named for the owner they cover (store, credentials, downloads, sync, pages, agents) |
| `CoreReadModelTests*.swift` | The Swift read model over the core's changes |
| `KeychainCredentialVaultTests.swift`, `SecurityCredentialKeychainStoreTests.swift` | Keychain access; the `CrestKeychainIntegration` scheme runs this target with `CREST_RUN_KEYCHAIN_INTEGRATION=1` |
| `WebKitEngineBindingErasureTests.swift`, `SpaceScrollGestureTests.swift` | WebKit binding erasure and Space gesture routing |
| `Support/` | Shared harnesses and fixtures: stored-session harness, privacy HTTP server, agent fixture, test-only extensions |
| `Fixtures/` | HTML read by path from tests: `BlockedPopups/`, `WebFocus/` |

## Depends on

The `Crest` target (`TEST_HOST`), `CrestContracts/include`, and the core
library that target embeds. `CrestNativeCoreTests` compiles the files its
`includes` lists from here against `CrestNativeCore` (`project.yml`), so a new file it should run must be added there. Run by
`Scripts/validate.sh` through the `Crest` scheme.

## Rules

- Default to no new test; add one only for a contract that breaks silently, and never test appearance (skill, "Tests").
- Remove temporary probes and redundant tests before handing off; never delete a failing test to go green (`AGENTS.md`, "Test retention and cleanup").
- Do not duplicate a shared contract in `CrestMobileTests/` unless the adapters diverge (skill, "Tests").
- Every test launch uses `CREST_ISOLATED_SESSION=1` (`Documentation/RepositoryGuardrails.md`, "Isolated validation sessions").
- `Fixtures/` stays out of the bundle and is read relative to `#filePath` (`project.yml`, `CrestTests` target).

## Read next

The owning feature's `CONTEXT.md`, then `Support/` before writing a new
harness, and `Documentation/RepositoryGuardrails.md` ("Focused guard tests").
