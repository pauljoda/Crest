<script lang="ts">
  import crestIcon from "../../../../../../CrestShared/Resources/AppIconPreviews.xcassets/CrestPreview.imageset/icon.png";
  import { emojiOf } from "../../branding";
  import SymbolIcon from "../../SymbolIcon.svelte";

  /**
   * A tab's icon, or its symbol while it has none. A site without an icon of
   * its own wears the engine's grey globe, as the Mac's tabs do.
   */
  let { icon, symbol, guide = false, size }: { icon: string | null; symbol: string; guide?: boolean; size: number } = $props();

  let failed = $state(false);
  // An emoji the person chose stands in for the site's icon.
  const emoji = $derived(emojiOf(symbol));
</script>

{#if emoji}
  <span class="tab-icon tab-emoji" style:width="{size}px" style:height="{size}px" style:font-size="{size * 0.85}px"
    aria-hidden="true">{emoji}</span>
{:else if guide}
  <img class="tab-icon" src={crestIcon} width={size} height={size} alt="" />
{:else if icon && !failed}
  <img class="tab-icon" src={icon} width={size} height={size} alt="" onerror={() => (failed = true)} />
{:else}
  <SymbolIcon name={symbol} {size} class={`tab-icon${symbol === "globe" ? " default-favicon" : ""}`} />
{/if}
