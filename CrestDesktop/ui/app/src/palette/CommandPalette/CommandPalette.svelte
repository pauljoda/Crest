<script lang="ts">
  import { untrack } from "svelte";
  import type { TransitionConfig } from "svelte/transition";

  import { closePalette, openPalette, type PaletteParts, setOverlayPresent } from "../palette-morph";
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
  $effect(() => {
    const target = area;
    if (!target) return;
    const measure = () => {
      size = { width: target.clientWidth, height: target.clientHeight };
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(target);
    return () => observer.disconnect();
  });
  const width = $derived(Math.min(metrics.maximumCardWidth, Math.max(0, size.width - 2 * metrics.cardPadding)));
  const resultsHeight = $derived(Math.max(metrics.minimumResultAreaHeight,
    Math.min(metrics.maximumResultAreaHeight, size.height - metrics.reservedHeight)));
  const top = $derived(Math.max(metrics.cardPadding, (size.height - (metrics.fieldHeight + resultsHeight)) / 2));

  let scrim = $state<HTMLDivElement>();
  let card = $state<HTMLDivElement>();
  let moving = $state<HTMLDivElement>();
  let resting = $state<HTMLDivElement>();
  let reveal = $state<HTMLDivElement>();
  let contents = $state<HTMLDivElement>();
  const parts = (): PaletteParts | null => {
    const [s, c, m, r, v, n] = [scrim, card, moving, resting, reveal, contents];
    return s && c && m && r && v && n ? { scrim: s, card: c, moving: m, resting: r, reveal: v, contents: n } : null;
  };
  // The palette comes in once its card is laid out where it rests; the scrim waits unseen until then.
  const laidOut = $derived(size.width > 0);
  let opened = false;
  $effect(() => {
    const found = parts();
    untrack(() => {
      if (opened) return;
      if (!found) {
        scrim?.style.setProperty("opacity", "0");
        return;
      }
      opened = true;
      void openPalette(found);
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
      void closePalette(found);
      const animations = [...found.card.getAnimations({ subtree: true }), ...found.scrim.getAnimations()];
      const ends = animations.map((animation) => Number(animation.effect?.getComputedTiming().endTime) || 0);
      return { duration: Math.max(0, ...ends) };
    };
  }
</script>

<div class="palette-layer" out:leave>
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div bind:this={scrim} class="palette-scrim" onmousedown={() => model.host.dismiss()}></div>
  <div class="palette-area" bind:this={area}>
    {#if laidOut}
      <div bind:this={card} class="palette-card" role="dialog" aria-label="Command Palette" style:width="{width}px" style:margin-top="{top}px">
        <div bind:this={moving} class="palette-glass moving" aria-hidden="true"></div>
        <div bind:this={resting} class="palette-glass resting" aria-hidden="true"></div>
        <div bind:this={reveal} class="palette-reveal">
          <div bind:this={contents} class="palette-contents">
            <SearchField {model} embedded={false} />
            {#if chips.length > 0}
              <ProviderChips {model} />
            {/if}
            <div class="palette-divider"></div>
            <ResultList {model} {bindings} {tabs} size={{ height: resultsHeight - (chips.length > 0 ? 44 : 0) }} />
          </div>
        </div>
      </div>
    {/if}
  </div>
</div>
