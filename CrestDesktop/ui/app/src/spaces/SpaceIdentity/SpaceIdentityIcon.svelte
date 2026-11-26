<script lang="ts">
  import { type SpaceBranding, SpaceIconStyleKinds } from "@crest/contracts";

  import { css, emojiOf } from "../../branding";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { accentFill, fillColorAt } from "../space-fills";
  import SpaceCrestIcon from "./SpaceCrestIcon.svelte";

  /** BrowserSpaceIdentityIcon: the crest, or the symbol at 56% of the icon, or the emoji at 68%. */
  let { symbol, branding, size }: { symbol: string; branding: SpaceBranding; size: number } = $props();

  const emoji = $derived(emojiOf(symbol));
</script>

{#if branding.iconStyle.kind === SpaceIconStyleKinds.LayeredCrest}
  <SpaceCrestIcon {branding} {size} />
{:else if emoji}
  <span class="space-identity-emoji" style:width="{size}px" style:height="{size}px" style:font-size="{size * 0.68}px">{emoji}</span>
{:else}
  <span class="space-identity-symbol" style:width="{size}px" style:height="{size}px" style:color={css(fillColorAt(accentFill(branding), 0.5))}>
    <SymbolIcon name={symbol} size={size * 0.56} strokeWidth={2.25} />
  </span>
{/if}
