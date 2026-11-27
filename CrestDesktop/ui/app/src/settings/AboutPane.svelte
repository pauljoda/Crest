<script lang="ts" module>
  const links = [
    // BrowserAboutLinks.
    { title: "Share Feedback on r/CrestBrowser", address: "https://www.reddit.com/r/CrestBrowser" },
    { title: "Report an Issue", address: "https://github.com/pauljoda/Crest/issues/new/choose" },
    { title: "View the Roadmap", address: "https://github.com/users/pauljoda/projects/3" },
  ];
</script>

<script lang="ts">
  import { OpenTab, TabPlacement } from "@crest/contracts";

  import AppIcon from "../shell/AppIcon.svelte";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { Group } from "./controls";
  import type { PaneProps } from "./panes.svelte";
  import { send } from "./preferences.svelte";
  import SoftwareUpdateGroup from "./SoftwareUpdateGroup.svelte";

  /** BrowserAboutSettingsPane: who Crest is, and where to talk about it. */
  let { session, shownSpace }: PaneProps = $props();

  const open = (address: string) => send(session, OpenTab({
    workspaceId: session.workspaceId, windowId: session.windowId, spaceId: shownSpace.id, tabId: crypto.randomUUID(),
    content: { address, view: null, title: null }, placement: TabPlacement.current, afterTabId: null, shows: true,
    placesAsNewTab: true, savesInSavedFolder: false,
  }));
</script>

<div class="settings-about">
  <AppIcon size={56} />
  <div>
    <div class="settings-about-name">Crest Browser</div>
    <div class="settings-about-version">Version {__CREST_VERSION__}</div>
  </div>
</div>
<SoftwareUpdateGroup />
<Group title="Community and support" footer="Reddit is public. Leave out private details.">
  {#each links as link (link.title)}
    <button type="button" class="settings-row settings-link-row" onclick={() => open(link.address)}>
      <span class="settings-row-title">{link.title}</span>
      <SymbolIcon name="arrow.up.right" size={12} class="settings-row-chevron" />
    </button>
  {/each}
</Group>
