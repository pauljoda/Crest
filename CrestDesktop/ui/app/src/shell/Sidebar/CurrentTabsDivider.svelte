<script lang="ts">
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { useAltHeld } from "./sidebar-parts.svelte";

  /**
   * BrowserCurrentTabsDivider on a pointer shell: the line between the saved
   * tabs and the open ones, and Clear at its trailing end while the pointer
   * rests over the Space's page and there is something to clear (styles.css).
   * Clear archives the open tabs but the shown one; holding Alt, as Option on
   * the Mac, makes it Clear All. The line stops short of the control.
   */
  let { canClearOthers, canClearAll, onClear }: {
    canClearOthers: boolean;
    canClearAll: boolean;
    onClear: (all: boolean) => void;
  } = $props();

  const alt = useAltHeld();
  const clearsAll = $derived(alt.current);
  const canClear = $derived(clearsAll ? canClearAll : canClearOthers);
</script>

<div class="current-tabs-divider" role="presentation">
  <span class="current-tabs-line"></span>
  {#if canClear}
    <button type="button" class="current-tabs-clear" data-testid="clear-current-tabs"
      aria-label={clearsAll ? "Clear All Tabs" : "Clear Other Tabs"}
      {...{ "aria-description": clearsAll ? "Moves all open tabs to Archive" : "Moves the other open tabs to Archive" }}
      onclick={() => onClear(clearsAll)}>
      <span>{clearsAll ? "Clear All" : "Clear"}</span>
      <SymbolIcon name="archivebox" size={11} />
      <SymbolIcon name="arrow.down" size={11} />
    </button>
  {/if}
</div>
