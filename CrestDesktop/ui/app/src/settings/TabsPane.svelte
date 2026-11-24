<script lang="ts">
  import { LinkBehavior, NewTabPosition, SavedTabClosePolicy } from "@crest/contracts";

  import { Group, Picker, Toggle } from "./controls";
  import type { PaneProps } from "./panes.svelte";
  import { appPreferences, defaults, setAppPreferences, useLinkPreferences } from "./preferences.svelte";

  /** BrowserTabsSettingsPane: new tabs, pinned and saved tabs, Split View and switching. */
  let { session }: PaneProps = $props();

  const preferences = $derived(appPreferences(session));
  const links = useLinkPreferences(() => session);
</script>

<Group title="New tabs" footer="Hold Shift as you open a link to do the opposite.">
  <Toggle title="Switch to tabs opened from links" checked={links.current?.focusesNewTabs ?? false} defaultValue={false}
    disabled={!links.current} onChange={(on) => links.setBehavior(LinkBehavior.focusesNewTabs, on)} />
  <Toggle title="Follow tabs moved to another Space" checked={links.current?.followsMovedTabs ?? true} defaultValue
    disabled={!links.current} onChange={(on) => links.setBehavior(LinkBehavior.followsMovedTabs, on)} />
  <Picker title="Open new tabs at" value={preferences.newTabPosition} defaultValue={defaults.newTabPosition}
    choices={NewTabPosition.all.map((value) => ({ value, label: value.title }))}
    onChange={(newTabPosition) => setAppPreferences(session, { newTabPosition })} />
  <Toggle title="Open new tabs in the current folder" checked={preferences.newTabsJoinFolder} defaultValue={defaults.newTabsJoinFolder}
    onChange={(newTabsJoinFolder) => setAppPreferences(session, { newTabsJoinFolder })} />
</Group>
<Group title="Pinned and saved tabs">
  <Picker title="After closing" value={preferences.savedTabClose} defaultValue={defaults.savedTabClose}
    choices={SavedTabClosePolicy.all.map((value) => ({ value, label: value.title }))}
    onChange={(savedTabClose) => setAppPreferences(session, { savedTabClose })} />
  <Toggle title="Keep saved tabs after unloading" checked={preferences.unloadedSavedTabsStay} defaultValue={defaults.unloadedSavedTabsStay}
    onChange={(unloadedSavedTabsStay) => setAppPreferences(session, { unloadedSavedTabsStay })} />
  <Toggle title="Click the favicon to return to the saved URL" checked={preferences.savedTabFaviconReturnsToSavedUrl}
    defaultValue={defaults.savedTabFaviconReturnsToSavedUrl}
    onChange={(savedTabFaviconReturnsToSavedUrl) => setAppPreferences(session, { savedTabFaviconReturnsToSavedUrl })} />
</Group>
<Group title="Split View">
  <Toggle title="Focus follows pointer" checked={preferences.splitFocusFollowsMouse} defaultValue={defaults.splitFocusFollowsMouse}
    onChange={(splitFocusFollowsMouse) => setAppPreferences(session, { splitFocusFollowsMouse })} />
</Group>
<Group title="Switching">
  <Toggle title="Show recent tabs while switching" checked={preferences.showsRecentTabs} defaultValue={defaults.showsRecentTabs}
    onChange={(showsRecentTabs) => setAppPreferences(session, { showsRecentTabs })} />
</Group>
