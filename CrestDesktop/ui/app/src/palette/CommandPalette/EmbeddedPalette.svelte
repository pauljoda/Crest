<script lang="ts">
  import { useOverlayPresent } from "../palette-morph";
  import { metrics, type PaletteProps, usePaletteVersion } from "./palette-view";
  import ProviderChips from "./ProviderChips.svelte";
  import ResultList from "./ResultList.svelte";
  import SearchField from "./SearchField.svelte";

  /**
   * The palette in place on a Start Page, as the Mac's embedded presentation:
   * no scrim and no close button, Escape only leaves a scope or a completion,
   * and the results show below the field once there are some, up to the
   * overlay's tallest.
   */
  let { model, bindings, tabs, obscured, takesFocus }: PaletteProps & {
    /** Whether the overlay palette covers this one, which then hides from assistive technology. */
    readonly obscured: boolean;
    /** Whether the field takes the keyboard as it opens, as the focused card's does. */
    readonly takesFocus: boolean;
  } = $props();
  const listId = $props.id();

  const chips = $derived.by(() => (usePaletteVersion(model), model.providerChips));
  const showsResults = $derived.by(() => (usePaletteVersion(model), model.groups.some((group) => group.items.length > 0)));
</script>

<div class={["palette-card embedded", useOverlayPresent() && "overlaid"]} aria-hidden={obscured || undefined}>
  <SearchField {model} embedded {takesFocus} {listId} />
  {#if chips.length > 0}
    <ProviderChips {model} />
  {/if}
  {#if showsResults}
    <div class="palette-divider"></div>
    <ResultList {model} {bindings} {tabs} {listId} size={{ maxHeight: metrics.maximumResultAreaHeight }} />
  {/if}
</div>
