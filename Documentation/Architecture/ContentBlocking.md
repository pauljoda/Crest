# Content blocking

Balanced protection applies EasyList and EasyPrivacy network rules, native CSS
hiding and their exceptions through WebKit on Mac, iPhone and iPad. A generic
third-party Funding Choices recovery-service block supplements those lists.
Each Space keeps its own on/off policy; Chromium continues to use extensions.

## Native rules

The core embeds a compressed, versioned snapshot. `BalancedProtectionRules`
validates it and returns the WebKit source and its SHA-256 cache identifier.
Only block, CSS display-none and exception actions are accepted. Top-level
document blocking is excluded. No remote JavaScript or scriptlets run.

WebKit compiles the snapshot once per launch's rule store. Named isolated
profiles use their own store; anonymous isolated launches use a temporary store.
Isolation never disables protection. Removing Crest's active lists preserves
extension-owned lists. Rule updates swap the lists on resident pages without
reloading their documents; policy changes retain the existing reload behavior.

## Refresh

Active Mac and mobile scenes check for updates in the background. The shared
provider downloads at most once a day from the snapshot in Crest's official
`main` branch, retries failures at most once an hour, and cancels with the scene.
Downloads use an ephemeral client with no cookies, credentials or browsing data.
Isolated validation sessions use bundled rules without automatic downloads.

Archives are limited to 4 MiB, expanded data to 64 MiB and native rules to
150,000. Core validation and WebKit compilation must both pass before an atomic
cache replacement. Older snapshots are rejected. Offline, malformed, oversized
or un-compilable updates leave the last working rules in use; the bundled
snapshot is the fallback when no valid cache exists.

## Updating the snapshot

Build SafariConverterLib v4.3.1's `ConverterTool` outside the checkout, then run:

```sh
python3 Scripts/update-content-blocking.py --converter /path/to/ConverterTool
Scripts/control-plane/generate-contracts.sh
Scripts/audit-licenses.py
```

Review and commit the resulting snapshot and dependency versions. Browsers
receive that reviewed snapshot without an app release once it reaches `main`.
The converter is an offline development tool; no converter code or foreign
runtime is linked into Crest. Filter data and its modifications remain
CC-BY-SA 3.0, with attribution in `EasyList-LICENSE.txt`.

## Limits

This is WebKit-native filtering, not the full uBlock engine. Unsupported
procedural selectors, redirects and scriptlets are omitted. Some ads, reserved
layout space, cookie notices or anti-adblock walls can remain. The generic
recovery-service block addresses one common wall without site-specific fixes.
The Space's existing protection control is the escape hatch for broken sites.
