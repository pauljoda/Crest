<script lang="ts">
  import type { SpaceBranding } from "@crest/contracts";

  import SymbolIcon from "../../SymbolIcon.svelte";
  import SpaceIdentityIcon from "./SpaceIdentityIcon.svelte";

  /**
   * A Space's identity as the Mac draws it everywhere it names a Space: its
   * layered crest, or its symbol or emoji in the symbol's color, with the lock
   * badge on a Space that asks for authentication (BrowserSpaceSymbolArtwork).
   */
  let { symbol, branding, locked, size, lockSize }: {
    symbol: string;
    branding: SpaceBranding;
    locked: boolean;
    size: number;
    lockSize: number;
  } = $props();
</script>

<span class="space-artwork" style:width="{size}px" style:height="{size}px" aria-hidden="true">
  <SpaceIdentityIcon {symbol} {branding} {size} />
  {#if locked}
    <span class="space-artwork-lock" style:padding="2px">
      <SymbolIcon name="lock.fill" size={lockSize} strokeWidth={3} />
    </span>
  {/if}
</span>
