# Sidepanel and shared-folder follow-ups

The core implementation is committed separately from the follow-ups below. This is a local development checkpoint, not a claim of full Chrome parity or distribution readiness. Mobile cold-start selection is already tracked as APP-306 in Crest 0.6.

## APP-311: mixed-version folder sync release gate

The new folder model reads prior Saved folders and migrates the intermediate currentTabFolders representation. Current-code round trips, sync projection/materialization and archive import/export are covered. That does not establish compatibility with an older Crest device.

Cloud records still advertise schema 1. Before this change, BrowserSyncPayload validation rejected folderID on Current tabs, and BrowserSyncFolder had no location field: the old materializer always created SavedFolder. An older reader can therefore reject Current-tab membership and interpret its accompanying folder as Saved. These findings come from the pre-change source, not a live mixed-version CloudKit test. No data-loss outcome is claimed.

Before distribution, define and test forward compatibility for folder and membership records across versions, including edits from the older device, tombstones, an offline upgrade and disabled sync sections. Do not address this merely by removing Current-folder sync, which is an explicit feature requirement. Keep the schema/migration decision separate from marketing version changes.

## APP-310: mobile drag polish

Core native pickup, cancellation, filing, outer-folder insertion and pinned/row shape changes have direct simulator evidence. Mobile drop now reveals the committed row immediately and fades the held native preview in place, avoiding the delayed landing handoff. A short visual change at release is accepted; a future polish pass must preserve immediate activation. Held preview edge clipping and exact destination sizing remain. A Time Profiler trace found no potential hangs but did not include frame-hitch lanes, so a 60/120fps result is unproven. Keep the next pass limited to these measured geometry and pacing issues; preserve the common folder tree and shared placement operation.

## Vendor and engine limits

Claude 1.0.90 anchors a conversation to its original group/tab. ChatGPT 1.26.827.12125 routes conversations by active tab. The one-document-per-Space host preserves its resource and delivers tab events; it cannot generically override either unchanged vendor's conversation policy. Do not fake IDs, silently regroup user tabs or reload on every selection.

WebKit's persistent DOM localStorage quota is separate from extension storage.local. ChatGPT's Statsig cache previously reached that limit. Subsequent reopen and repeated capture passed after isolated recovery, but future cache growth remains a vendor/engine constraint. No automatic vendor-key deletion or replacement localStorage implementation is included.

Core CDP Fetch operations work, but authentication interception, streams and several detailed Chrome semantics remain unsupported as listed in the API compatibility matrix. Add capabilities for a demonstrated required vendor operation and a feasible engine path.

Sidepanel content isolation currently uses the guarded WebKit _setUserContentController: SPI on navigation preferences. The implementation refuses an isolated panel if that capability is unavailable. Retain the supported-OS validation gate and revisit the adapter when a suitable public API exists.
