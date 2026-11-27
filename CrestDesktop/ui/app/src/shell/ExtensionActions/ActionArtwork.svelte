<script lang="ts">
  import SymbolIcon from "../../SymbolIcon.svelte";
  import type { ActionPresentation } from "./extension-actions.svelte";

  /** An action's icon, with its badge where it has one, as BrowserExtensionActionArtwork draws them. */
  let { action, size }: { action: ActionPresentation; size: number } = $props();
</script>

<span class="extension-artwork" style:width="{size}px" style:height="{size}px">
  {#if action.iconUrl}
    <img src={action.iconUrl} alt="" width={size} height={size} />
  {:else}
    <SymbolIcon name="puzzlepiece.extension" {size} />
  {/if}
  {#if action.badge}<span class="extension-badge">{action.badge}</span>{/if}
</span>
