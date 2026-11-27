<script lang="ts">
  import type { InstalledExtension } from "@crest/contracts";

  import SymbolIcon from "../SymbolIcon.svelte";
  import { Switch } from "./controls";

  /** BrowserExtensionRow: the icon, name, version and summary, its switch, and the rest behind a disclosure. */
  let { item, icon, setEnabled, options, manage, remove, copy }: {
    item: InstalledExtension;
    icon: string | null;
    setEnabled: (on: boolean) => void;
    options: () => void;
    manage: () => void;
    remove: () => void;
    copy: () => void;
  } = $props();

  let open = $state(false);
</script>

<div class="settings-extension">
  <div class="settings-row">
    <button type="button" class="settings-disclosure" aria-expanded={open} aria-label={`${item.name} details`} onclick={() => (open = !open)}>
      <SymbolIcon name={open ? "chevron.down" : "chevron.right"} size={10} />
    </button>
    <span class="settings-extension-icon">{#if icon}<img src={icon} alt="" />{:else}<SymbolIcon name="puzzlepiece.extension" size={16} />{/if}</span>
    <div class="settings-row-text">
      <span class="settings-row-title">
        <span class="settings-truncates">{item.name}</span>
        <span class="settings-extension-version">{item.version}</span>
      </span>
      {#if item.description}<span class="settings-row-subtitle settings-clamps">{item.description}</span>{/if}
      {#if item.fromWebStore}<span class="settings-row-subtitle settings-extension-source">From Chrome Web Store</span>{/if}
    </div>
    <Switch label={`${item.name} enabled`} checked={item.enabled} disabled={!item.changeable} onChange={setEnabled} />
  </div>
  {#if open}
    <div class="settings-extension-details">
      {#if item.fromWebStore}<button type="button" class="settings-link-button" onclick={copy}>Install a copy in other spaces</button>{/if}
      {#if item.permissions.length > 0}
        <div class="settings-extension-permissions">
          <strong>Permissions and Website Access</strong>
          {#each item.permissions as permission}<span>{permission}</span>{/each}
        </div>
      {/if}
      <button type="button" class="settings-link-button" onclick={manage}>
        <SymbolIcon name="hand.raised" size={12} /> Manage Permissions in Chromium
      </button>
      {#if item.optionsUrl && item.enabled}
        <button type="button" class="settings-link-button" onclick={options}>
          <SymbolIcon name="gearshape" size={12} /> Extension Settings
        </button>
      {/if}
      {#if item.changeable}
        <button type="button" class="settings-link-button destructive" onclick={remove}>
          <SymbolIcon name="trash" size={12} /> Remove Extension
        </button>
      {/if}
    </div>
  {/if}
</div>
