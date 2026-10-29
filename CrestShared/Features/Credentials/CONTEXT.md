# CrestShared/Features/Credentials

The Crest Passwords UI on every shell: the prompts a page raises (suggest a
saved password, generate a strong one, save or update one, warn about a
cross-origin credential), the credential detail view that Settings opens, and
passkey access. Which prompt shows comes from
`BrowserCredentialChromePresentation`; what it may do to the page comes from
the fill and save ports.

## Goal

One credential surface whose prompts and detail view behave the same on both
engines and both shells.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserCredentialChrome/` | The page's credential prompts: suggestion, strong password, save, header, error and cross-origin notice; placement and metrics; `BrowserCredentialFillPort` and `BrowserCredentialSavePort` |
| `BrowserCredentialDetailView/` | One credential's account, password and error sections, its model and request, and a preview fixture |
| `BrowserPasskeyAccessView/` | The passkey access view over the app's passkey controller |
| `Models/` | Save-prompt state, route and the performer of its primary action |

## Depends on

`CrestShared/Application/Credentials/` (suggestions and Keychain models),
`CrestShared/Infrastructure/Credentials/` (sensitive access),
`CrestShared/Application/BrowserPasskeyAccess/`, `BrowserStore`,
`BrowserSpaceAccessController`, `Spaces/` (Space identity). Used by
`Settings/BrowserPasswordSettingsPane/` and the page surfaces in
`CrestMac/Features/Browser/` and `CrestMobile/Features/Browser/`.

## Rules

- Credentials are matched by origin and belong to a Space, which can turn off Crest's suggestions, generation, save prompts and HTTP-auth reuse (`Documentation/ARCHITECTURE.md`, "Credentials and privacy", "Space isolation").
- Sensitive reveals and exports require device authentication (`Documentation/ARCHITECTURE.md`, "Credentials and privacy").
- Page-to-app credential messages are schema-checked and origin-bound (`Documentation/ARCHITECTURE.md`, "Credentials and privacy").
- Crest does not intercept WebAuthn: WebKit handles credential requests itself and Chromium sends them to the system passkey sheet (`Documentation/ARCHITECTURE.md`, "Credentials and privacy").
- Privacy, authorization and Keychain contracts are where permanent tests belong (skill, "Tests").

## Read next

`Documentation/ARCHITECTURE.md` ("Credentials and privacy", "Engine
boundary"), then `CrestShared/Infrastructure/Credentials/`.
