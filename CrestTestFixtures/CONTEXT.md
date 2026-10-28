# CrestTestFixtures

Web pages and a local server for validating Crest in a running app:
compatibility, performance, offline, popup, download, frame, worker and media
fixtures. They are served to the browser, not compiled into a target.

## Goal

A small, stable corpus that exercises real page behavior with exact request
and byte counts.

## Contents

| File | What it is |
| --- | --- |
| `network-server.py` | Serves the corpus with request and byte counters, optional TLS and a metrics file |
| `compatibility.html`, `performance.html`, `physical-offline.html` | The compatibility corpus, the performance fixture, the offline fixture |
| `popup.html`, `frame.html`, `download.txt`, `data.json`, `sample.mp4` | Popup routing, frames, downloads, fetches and media |
| `service-worker.js`, `worker.js` | Service and dedicated worker scripts |

## Depends on

Nothing in the build. `Scripts/validate-identity.sh` requires the folder to
exist.

## Rules

- Launches against these fixtures use `CREST_ISOLATED_SESSION=1` (`Documentation/RepositoryGuardrails.md`, "Isolated validation sessions").
- Consolidate fixtures instead of adding one per task; temporary fixtures come out before handing off (`AGENTS.md`, "Test retention and cleanup").
- Results and logs from a run never enter the tree (`AGENTS.md`, "Test retention and cleanup").

## Read next

`CrestTests/CONTEXT.md` for the fixtures tests read by path
(`CrestTests/Fixtures/`).
