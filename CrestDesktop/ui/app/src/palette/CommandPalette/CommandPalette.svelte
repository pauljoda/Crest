<script lang="ts">
  import { untrack } from "svelte";
  import type { TransitionConfig } from "svelte/transition";

  import { closePalette, openPalette, pageAddressField, type PaletteParts, setOverlayPresent } from "../palette-morph";
  import { metrics, type PaletteProps, usePaletteVersion } from "./palette-view";
  import ProviderChips from "./ProviderChips.svelte";
  import ResultList from "./ResultList.svelte";
  import SearchField from "./SearchField.svelte";

  /**
   * The command palette over a window, as the Mac's overlay shows it: a scrim
   * over the whole window, and the card centered over the page, its top edge
   * where a card with its tallest results would sit centered, growing only
   * downward. It grows out of the sidebar's address field and shrinks back
   * into it (`palette-morph.ts`), its glass apart from its contents so each
   * keeps its own pace.
   */
  let { model, bindings, tabs }: PaletteProps = $props();

  const chips = $derived.by(() => (usePaletteVersion(model), model.providerChips));

  // The element's size, kept current as it resizes.
  let area = $state<HTMLDivElement>();
  let size = $state.raw({ width: 0, height: 0 });
  let drop = $state.raw<{ left: number; top: number; width: number; radius: string; results: number } | null>(null);
  $effect(() => {
    const target = area;
    if (!target) return;
    const field = pageAddressField();
    const measure = () => {
      if (field) {
        const box = field.getBoundingClientRect();
        const areaBox = target.getBoundingClientRect();
        const margin = 8;
        const wanted = Math.max(box.width, 440);
        const rtl = getComputedStyle(field).direction === "rtl";
        const leading = wanted >= innerWidth - margin * 2 ? margin : Math.max(margin, rtl ? innerWidth - box.right : box.left);
        const width = Math.max(0, Math.min(wanted, innerWidth - leading - margin));
        drop = { left: (rtl ? innerWidth - leading - width : leading) - areaBox.left, top: box.top - areaBox.top, width, radius: getComputedStyle(field).borderTopLeftRadius,
          results: Math.max(0, Math.min(metrics.maximumResultAreaHeight, innerHeight - box.top - margin - 37)) };
      }
      size = { width: target.clientWidth, height: target.clientHeight };
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(target);
    if (field) observer.observe(field);
    return () => observer.disconnect();
  });
  const width = $derived(Math.min(metrics.maximumCardWidth, Math.max(0, size.width - 2 * metrics.cardPadding)));
  const resultsHeight = $derived(Math.max(metrics.minimumResultAreaHeight,
    Math.min(metrics.maximumResultAreaHeight, size.height - metrics.reservedHeight)));
  const top = $derived(Math.max(metrics.cardPadding, (size.height - (metrics.fieldHeight + resultsHeight)) / 2));

  let scrim = $state<HTMLDivElement>();
  let card = $state<HTMLDivElement>();
  let glass = $state<HTMLDivElement>();
  let reveal = $state<HTMLDivElement>();
  let contents = $state<HTMLDivElement>();
  const parts = (): PaletteParts | null => {
    return scrim && card && glass && reveal && contents ? { scrim, card, glass, reveal, contents } : null;
  };
  // The palette comes in once its card is laid out where it rests; the scrim waits unseen until then.
  const laidOut = $derived(size.width > 0);
  let opened = false;
  let leaving = false;
  $effect(() => {
    const found = parts();
    // Svelte can reuse the departing layer for a palette reopened during its outro.
    void model;
    untrack(() => {
      if (opened && !leaving) return;
      if (!found) {
        scrim?.style.setProperty("opacity", "0");
        return;
      }
      opened = true;
      void openPalette(found, leaving);
      leaving = false;
    });
  });
  $effect(() => {
    setOverlayPresent(true);
    return () => setOverlayPresent(false);
  });

  /**
   * It leaves once it has shrunk back into the field, or faded where it
   * rests: the palette stays for as long as the last part of the morph takes
   * to land. Deferred, so Svelte asks again each time it is taken away.
   */
  function leave(_node: Element): () => TransitionConfig {
    return () => {
      const found = parts();
      if (!found || !opened) return { duration: 0 };
      // Leaving runs once, as the palette is taken away.
      leaving = true;
      void closePalette(found);
      const animations = [...found.card.getAnimations({ subtree: true }), ...found.scrim.getAnimations()];
      const ends = animations.map((animation) => Number(animation.effect?.getComputedTiming().endTime) || 0);
      return { duration: Math.max(0, ...ends) };
    };
  }
</script>

<div class="palette-layer" class:dropping={!!drop} out:leave>
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div bind:this={scrim} class="palette-scrim" onmousedown={() => model.host.dismiss()}></div>
  <div class="palette-area" bind:this={area}>
    {#if laidOut}
      <div bind:this={card} class="palette-card" role="dialog" aria-label="Command Palette" class:dropping={!!drop} style:--address-radius={drop?.radius} style:width="{drop?.width ?? width}px" style:left={drop ? `${drop.left}px` : undefined}
        style:margin-top="{drop?.top ?? top}px">
        <div bind:this={glass} class="palette-glass" aria-hidden="true"></div>
        <div bind:this={reveal} class="palette-reveal">
          <div bind:this={contents} class="palette-contents">
            <SearchField {model} embedded={false} inline={!!drop} />
            {#if chips.length > 0}
              <ProviderChips {model} />
            {/if}
            <div class="palette-divider"></div>
            <ResultList {model} {bindings} {tabs} size={drop ? { maxHeight: Math.max(0, drop.results - (chips.length > 0 ? 44 : 0)) } : { height: resultsHeight - (chips.length > 0 ? 44 : 0) }} />
          </div>
        </div>
      </div>
    {/if}
  </div>
</div>
