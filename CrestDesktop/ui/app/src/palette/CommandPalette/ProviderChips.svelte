<script lang="ts">
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { type PaletteModel, providerActionTitle } from "../palette-model";
  import { brandColor, usePaletteVersion } from "./palette-view";
  import ProviderIcon from "./ProviderIcon.svelte";

  /** The providers what is typed names, as chips under the field; clicking one enters it. */
  let { model }: { model: PaletteModel } = $props();

  const providers = $derived.by(() => (usePaletteVersion(model), model.providerChips));
</script>

<div class="palette-provider-chips" role="group" aria-label="Search providers">
  {#each providers as provider, index (provider.name)}
    <button type="button" class="palette-chip interactive" style:--chip-tint={brandColor(provider.color)}
      title={providerActionTitle(provider)} onmousedown={(event) => event.preventDefault()}
      onclick={() => model.enterProvider(provider)}>
      <ProviderIcon {provider} />
      {#if provider.shortcuts[0]}
        <span class="palette-chip-title shortcut">{provider.shortcuts[0]}</span>
      {:else}
        <span class="palette-chip-title">{provider.title}</span>
      {/if}
      {#if index === 0}
        <SymbolIcon name="arrow.right.to.line" size={10} />
      {/if}
    </button>
  {/each}
</div>
