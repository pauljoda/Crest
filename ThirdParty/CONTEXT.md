# ThirdParty

Retained license notices for code and data Crest redistributes: Chromium,
.NET, Sparkle and Unicode data. Each notice is named by an entry in
`Config/ThirdPartyDependencies.json`.

## Goal

Ship every redistributed dependency with its preserved notice.

## Contents

| File | What it is |
| --- | --- |
| `Chromium-LICENSE.txt` | The Chromium engine |
| `DotNet-LICENSE.txt` | The .NET runtime compiled into the core |
| `Sparkle-LICENSE.txt` | Sparkle, the Mac updater |
| `Unicode-LICENSE.txt` | Unicode emoji test data behind the emoji picker |

## Depends on

Nothing. Referenced from `Config/ThirdPartyDependencies.json` and checked by
`Scripts/audit-licenses.py`. Adapted Chromium code keeps its own notices in
`CrestEngines/Chromium/ThirdParty/`.

## Rules

- A new runtime dependency needs a redistributable license and a preserved notice before it lands, and `Scripts/audit-licenses.py` must pass (`CONTRIBUTING.md`, "Validation").

## Read next

`Config/ThirdPartyDependencies.json`, then `Scripts/audit-licenses.py`.
