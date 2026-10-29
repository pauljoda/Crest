# Credentials

The core's credential and passkey rules, as questions that keep no state:
what a form observation does, whether a fill or save may happen, which record
an account matches, how to compose a generated password, whether passkeys
and the system's Passwords app are available, and how password files import
and export. Crest Passwords themselves live in the platform's Keychain.

## Goal

Credential policy decided once in the core while no password is ever stored,
staged or synced by it.

## Contents

| Path | What it is |
| --- | --- |
| `CredentialFile.cs` | A password file as the core reads it: format, rows kept and rows left out |
| `CredentialFileColumn.cs` | The column headers each browser and password manager uses |
| `Queries/` | Capture, fill, save, save check and match, most recent credential, strong password recipe, password-file and browser-password import previews, export, passkey access, system Passwords offer and write-through |

## Depends on

`Contracts/Credentials/` (`Files/` for import and export) and
`Contracts/Passkeys/`, `Domain/Csv/`. Swift's side is
`CrestShared/Features/Credentials/` and `CrestShared/Infrastructure/Credentials/`;
setup's import commit (`Application/Device/Intents/Setup/`) brackets the
passwords the platform imports. `CredentialFile` reads and writes through
`Domain/Csv/`.

## Rules

- The credential questions keep no state; importing and exporting a password file are the only questions that carry passwords, answered from the question alone (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- A record that holds a password is `[HoldsSecrets]`; no change, intent, stored session, device record or sync journal may reach it, which `CrestCore/tests/CrestCore.Tests/Credentials/SecretContainmentTests.cs` checks (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- A generated password never exists in the core; it answers only the recipe (`CrestCore/src/CrestCore/Application/Credentials/Queries/StrongPassword.cs`, its doc comment).
- Credentials are matched by origin; each Space can turn off Crest's suggestions, generation, save prompts and HTTP-auth reuse (`Documentation/ARCHITECTURE.md`, "Credentials and privacy").
- Privacy and authorization boundaries and Keychain access are contracts worth a permanent test (`.agents/skills/crest-contribution/SKILL.md`, "Tests").

## Read next

`Documentation/ARCHITECTURE.md` ("Credentials and privacy"), then
`CrestCore/tests/CrestCore.Tests/Credentials/`.
