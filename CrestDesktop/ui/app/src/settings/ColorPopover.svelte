<script lang="ts" module>
  import type { BrandColor } from "@crest/contracts";

  import { sameColor } from "../spaces/color-harmony";
  import { cuspLightness, fromLch, type SpaceFill } from "../spaces/space-fills";

  /** The spectrum: a hue every 30° from a red, at one soft chroma, each leaning toward the lightness where it is most vivid. */
  const spectrum: readonly { readonly name: string; readonly color: BrandColor }[] = [
    "Red", "Orange", "Yellow", "Lime", "Green", "Mint", "Teal", "Sky", "Blue", "Violet", "Purple", "Pink",
  ].map((name, step) => {
    const degrees = 25 + step * 30;
    const lightness = 0.7 + 0.4 * (cuspLightness(degrees) - 0.7);
    return { name, color: fromLch(lightness, 0.12, degrees / 360) };
  });

  /** Whether two fills draw the same: their colors, and, for a gradient, its kind and direction. */
  export function sameFill(left: SpaceFill, right: SpaceFill): boolean {
    if (left.colors.length !== right.colors.length) return false;
    if (!left.colors.every((color, index) => sameColor(color, right.colors[index]))) return false;
    return left.colors.length < 2 || (left.kind === right.kind && Math.abs(left.degrees - right.degrees) < 0.5);
  }
</script>

<script lang="ts">
  import { entranceScale, motion as tokens } from "@crest/design";
  import { untrack } from "svelte";

  import { css } from "../branding";
  import { presence, reducesMotion } from "../motion";
  import { ColorStops, edgeLightness, maximumFillColors, readWheel, wheelColor, withLightness } from "../spaces/color-harmony";
  import SymbolIcon from "../SymbolIcon.svelte";
  import AngleKnob from "./AngleKnob.svelte";
  import { metrics, type Placing } from "./color-popover";
  import ColorSlider from "./ColorSlider.svelte";
  import ColorWheel from "./ColorWheel.svelte";

  /**
   * CrestColorPopover's content: the color wheel with a handle for each of
   * the fill's colors; minus and plus under it, with the gradient's direction
   * and the link at either end once there are two colors; the chosen color's
   * Brightness; the Texture where the well has one; and the spectrum. Every
   * gradient it touches runs straight. It edits its own copy, which reaches
   * `onCommit` at most every 33 ms, and further apart while the window is
   * still drawing the last one; `flush` hands over what is pending at once,
   * as the popover closes.
   */
  let { fill, onCommit, texture = null, flush }: {
    fill: SpaceFill;
    onCommit: (fill: SpaceFill) => void;
    texture?: { readonly value: number; readonly onChange: (value: number) => void } | null;
    flush: { current: (() => void) | null };
  } = $props();

  const reduced = $derived(reducesMotion());
  const stops = new ColorStops();
  stops.adopt(untrack(() => fill));
  let draft = $state.raw(untrack(() => fill));
  let selection = $state(0);
  let isLinked = $state(true);
  let placing = $state<Placing>("instant");
  let pending: number | null = null;
  let pace: number = metrics.commitInterval;

  /** Hands the copy over once the pace has passed; waking late slows the pace, waking on time quickens it. */
  const schedule = () => {
    if (pending !== null) return;
    const wait = pace;
    const asked = performance.now();
    pending = window.setTimeout(() => {
      const late = performance.now() - asked - wait;
      pace = late > metrics.lateness
        ? Math.min(wait + late, metrics.slowestCommitInterval)
        : Math.max(wait - metrics.paceStep, metrics.commitInterval);
      pending = null;
      onCommit(draft);
    }, wait);
  };

  const edit = (next: SpaceFill, how: Placing = "instant") => {
    draft = next;
    placing = how;
    selection = Math.min(selection, next.colors.length - 1);
    schedule();
  };

  $effect(() => {
    untrack(() => {
      // Every gradient runs straight; one of another kind takes a line, which counts as an edit.
      if (draft.colors.length > 1 && draft.kind !== "linear") edit({ ...draft, kind: "linear" });
    });
  });

  // A change from elsewhere, with nothing of the popover's own pending, takes over the copy.
  $effect(() => {
    const incoming = fill;
    untrack(() => {
      if (pending !== null || sameFill(incoming, draft)) return;
      draft = incoming;
      stops.adopt(incoming);
      stops.releaseShape();
    });
  });

  $effect(() => {
    const target = flush;
    const commitNow = () => {
      if (pending === null) return;
      window.clearTimeout(pending);
      pending = null;
      onCommit(draft);
    };
    untrack(() => (target.current = commitNow));
    return () => {
      commitNow();
      target.current = null;
    };
  });

  const chosenIndex = $derived(Math.min(selection, draft.colors.length - 1));
  const chosen = $derived(readWheel(draft.colors[chosenIndex]));
  const isGradient = $derived(draft.colors.length > 1);

  const move = (color: BrandColor, index: number, how: Placing = "instant") => {
    edit(stops.move(color, index, draft, isLinked), how);
  };

  const add = () => {
    const next = stops.add(draft);
    edit(next, "spring");
    selection = next.colors.length - 1;
  };

  const remove = () => {
    const index = chosenIndex;
    const next = stops.remove(index, draft);
    edit(next, "spring");
    selection = Math.min(index, next.colors.length - 1);
  };

  const toggleLink = () => {
    isLinked = !isLinked;
    stops.releaseShape();
  };

  const selectionMotion = $derived(reduced ? { duration: 0 } : tokens.selection);
</script>

<div class="color-popover-content">
  <div class="color-popover-wheel-group">
    <ColorWheel fill={draft} ids={stops.ids(draft)} selection={chosenIndex} {placing} reducesMotion={reduced}
      onChoose={(index) => (selection = index)}
      onPlace={(color, index, springs) => move(color, index, springs ? "spring" : "instant")} />
    <div class="color-popover-controls">
      <div class="color-popover-count">
        <button type="button" class="color-popover-button" aria-label="Remove Color" title="Remove Color"
          disabled={draft.colors.length <= 1} onclick={remove}>
          <SymbolIcon name="minus" size={17} strokeWidth={2.25} />
        </button>
        <button type="button" class="color-popover-button" aria-label="Add Color" title="Add Color"
          disabled={draft.colors.length >= maximumFillColors} onclick={add}>
          <SymbolIcon name="plus" size={17} strokeWidth={2.25} />
        </button>
      </div>
      {#if isGradient}
        <div class="color-popover-leading"
          in:presence={{ pose: { opacity: 0, scale: entranceScale }, timing: selectionMotion }}
          out:presence={{ pose: { opacity: 0, scale: entranceScale }, timing: selectionMotion }}>
          <AngleKnob degrees={draft.degrees} onChange={(degrees) => edit({ ...draft, degrees })} />
        </div>
        <div class="color-popover-trailing"
          in:presence={{ pose: { opacity: 0, scale: entranceScale }, timing: selectionMotion }}
          out:presence={{ pose: { opacity: 0, scale: entranceScale }, timing: selectionMotion }}>
          <button type="button" class={`color-link${isLinked ? " on" : ""}`} data-testid="color-link"
            aria-label={isLinked ? "Unlink Colors" : "Link Colors"} aria-pressed={isLinked} title={isLinked ? "Unlink Colors" : "Link Colors"}
            onclick={toggleLink}>
            <SymbolIcon name="link" size={16} strokeWidth={2.25} />
          </button>
        </div>
      {/if}
    </div>
  </div>
  <ColorSlider title="Brightness" value={chosen.lightness}
    track={Array.from({ length: metrics.trackSteps + 1 }, (_, step) => wheelColor(withLightness(chosen, step / metrics.trackSteps)))}
    thumb={draft.colors[chosenIndex]}
    onChange={(value) => move(wheelColor(withLightness(chosen, Math.min(Math.max(value, edgeLightness), 1 - edgeLightness))), chosenIndex)} />
  {#if texture}
    <ColorSlider title="Texture" value={texture.value} track={[draft.colors[0], draft.colors[0]]} thumb={draft.colors[0]} showsGrain
      onChange={texture.onChange} />
  {/if}
  <div class="color-spectrum" role="group" aria-label="Spectrum">
    {#each spectrum as { name, color } (name)}
      {@const selected = sameColor(draft.colors[chosenIndex], color)}
      <span class="color-spectrum-slot">
        <button type="button" class={`color-spectrum-swatch${selected ? " selected" : ""}`} aria-label={name} aria-pressed={selected}
          title={name} onclick={() => move(color, chosenIndex, "spring")}>
          <span class="color-spectrum-dot" style:background={css(color)}></span>
        </button>
      </span>
    {/each}
  </div>
</div>
