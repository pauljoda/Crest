<script lang="ts" module>
  /** A provider's icon on its paper plate: the kind's symbol until the providers' logos ship here. */
  /** The search providers' logos, shared with the Mac, by asset name. */
  const providerLogos: Record<string, string> = Object.fromEntries(
    Object.entries(import.meta.glob<string>("../../../../../../CrestShared/Resources/SearchProviderLogos.xcassets/*/*@2x.png", {
      eager: true,
      query: "?url",
      import: "default",
    })).map(([path, url]) => [path.split("/").at(-2)?.replace(/\.imageset$/, "") ?? "", url]),
  );
</script>

<script lang="ts">
  import type { SearchProvider } from "@crest/contracts";

  import SymbolIcon from "../../SymbolIcon.svelte";

  /** A provider's logo where it has one, as the Mac's BrowserSearchProviderIcon draws it, else its kind's glyph. */
  let { provider, size = 14 }: { provider: SearchProvider; size?: number } = $props();

  const logo = $derived(provider.logo ? providerLogos[provider.logo] : undefined);
</script>

{#if logo}
  <img class="palette-provider-logo" src={logo} width={size} height={size} alt="" />
{:else}
  <span class="palette-provider-icon" style:width="{size + 6}px" style:height="{size + 6}px">
    <SymbolIcon name={provider.kind.symbol} size={Math.round(size * 0.65)} />
  </span>
{/if}
