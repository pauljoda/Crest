# HelpCenter

Crest Help, the user guides, as a Docusaurus site. CI checks it on every
pull request with `npm run build`; `npm run build:website` writes the
published build into `Website/guides/`, served under `crestbrowser.com/guides/`.

## Goal

Explain what a person can do in Crest, one task per page, in the product's
own words.

## Contents

| Path | What it is |
| --- | --- |
| `docs/` | The guides by topic: `browsing/`, `extensions/`, `getting-started/`, `privacy/`, `spaces/`, `tabs/`, and `index.mdx` |
| `src/` | `components/` (`GuideScreenshot`, `HelpSearch`) and `css/custom.css` |
| `static/` | The logo, guide screenshots under `img/guides/<slug>/`, and the 1Password placeholder page |
| `plugins/` | `help-search-index`, the search index builder |
| `scripts/` | `sanitize-build-output.js`, run after every build |
| `docusaurus.config.js`, `sidebars.js` | Site configuration (base URL `/guides/`) and navigation |
| `package.json`, `package-lock.json` | Dependencies and the `build` and `build:website` scripts |

## Depends on

Node.js 20 or later (`CONTRIBUTING.md`, "Local setup"). Checked with
`npm run build` by the **Website and Help Center** job in
`.github/workflows/ci.yml`. `npm run build:website` writes `Website/guides/`,
which `.github/workflows/pages.yml` deploys.

## Rules

- Keep the Google-free protection and Web Push limitations accurate when an engine is published (`CrestEngines/Chromium/README.md`, "Releasing").
- Screenshots go under `static/img/guides/<slug>/` through `GuideScreenshot`, with alt text (`static/img/guides/README.md`).
- A changed website dependency runs `Scripts/audit-licenses.py` (`CONTRIBUTING.md`, "Validation").
- No task reports or dated narratives in the guides (`AGENTS.md`, "Test retention and cleanup").

## Read next

The guide being changed, then `Website/CONTEXT.md` for how the build is
published.
