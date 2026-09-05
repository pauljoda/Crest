# Sidepanel and shared-folder follow-ups

The core implementation is committed separately from the follow-ups below. This is a local development checkpoint, not a claim of full Chrome parity or distribution readiness. Mobile cold-start selection is already tracked as APP-306 in Crest 0.6.

## APP-311: best-effort mixed-version folder sync

Open folders and their Current-tab memberships use cloud record schema 2. Saved folders, ordinary tabs and tombstones continue using schema 1. Older readers that reject newer schemas can therefore skip unsupported folders while continuing to process familiar records. Updating both platforms is the supported way to keep the full folder structure aligned; no parallel legacy folder model or separate sync store is introduced.

When cloud schema support increases, Crest clears the persisted CKSyncEngine cursor and cached change tags so records skipped before the update are fetched again. The session, local journal, sync preferences and account-change decision are retained. Cloud schema versioning is separate from the local journal format. The metadata cache now preserves each server record's schema, and encoding refuses a cached record from a future schema before changing its payload.

This is deliberately best-effort compatibility, as requested. Already-shipped clients cannot acquire the new write guard: they may retain stale Saved copies or overwrite records during concurrent edits. The schema marker does not prevent that older-writer behavior. No claim of perfect old/new convergence or live mixed-version CloudKit validation is made. Current-version cloud codec, journal/materialization, nested folders, disabled sections, return-to-Saved, tombstone and upgrade-state tests cover the implemented behavior.

## APP-310: mobile drag polish

Core native pickup, cancellation, filing, outer-folder insertion and pinned/row shape changes have direct simulator evidence. Mobile drop now reveals the committed row immediately and fades the held native preview in place, avoiding the delayed landing handoff. A short visual change at release is accepted; a future polish pass must preserve immediate activation. Held preview edge clipping and exact destination sizing remain. A Time Profiler trace found no potential hangs but did not include frame-hitch lanes, so a 60/120fps result is unproven. Keep the next pass limited to these measured geometry and pacing issues; preserve the common folder tree and shared placement operation.

## Vendor and engine limits

Claude 1.0.90 anchors a conversation to its original group/tab. ChatGPT 1.26.827.12125 routes conversations by active tab. The one-document-per-Space host preserves its resource and delivers tab events; it cannot generically override either unchanged vendor's conversation policy. Do not fake IDs, silently regroup user tabs or reload on every selection.

WebKit's persistent DOM localStorage quota is separate from extension storage.local. ChatGPT's Statsig cache previously reached that limit. Subsequent reopen and repeated capture passed after isolated recovery, but future cache growth remains a vendor/engine constraint. No automatic vendor-key deletion or replacement localStorage implementation is included.

Core CDP Fetch operations work, but authentication interception, streams and several detailed Chrome semantics remain unsupported as listed in the API compatibility matrix. Add capabilities for a demonstrated required vendor operation and a feasible engine path.

Sidepanel content isolation currently uses the guarded WebKit _setUserContentController: SPI on navigation preferences. The implementation refuses an isolated panel if that capability is unavailable. Retain the supported-OS validation gate and revisit the adapter when a suitable public API exists.
