<script lang="ts">
  import { untrack } from "svelte";

  import { presence, type Timing } from "../motion";
  import { holdLiveResize } from "./PageCard.svelte";
  import { holdPointer } from "./pointer-hold";
  import { liftOut } from "./row-motion";
  import { splitMetrics } from "./shown-cards";

  /**
   * BrowserSplitCardResizeHandle: the gap between two cards, which overhangs
   * each by a little so it is comfortable to take without covering either,
   * with a capsule that stays visible at rest. A drag measures the pointer's
   * whole travel from where it began, and arrow keys step it as a complete
   * resize each.
   */
  let { index, interactive, shows, shares, transition, resize, commit }: {
    index: number;
    interactive: boolean;
    /** Whether the gap carries a divider, which none does while a gesture is in flight. */
    shows: boolean;
    shares: readonly number[];
    transition: Timing;
    resize: (delta: number, baseline: readonly number[]) => void;
    commit: (shares: readonly number[]) => void;
  } = $props();

  // Releasing lets go of the pointer and of the pages, which the drag resizes each move.
  let drag: { pointerId: number; x: number; baseline: readonly number[]; release: () => void } | null = null;
  let active = $state(false);
  const finish = () => {
    const begun = drag;
    if (!begun) return;
    drag = null;
    active = false;
    begun.release();
    commit(shares);
  };
  $effect(() => () => drag?.release());

  // A divider that goes fades on the row's motion as it last stood with it,
  // as a leaving child keeps the props it last had.
  let shownTransition = untrack(() => transition);
  $effect(() => {
    shownTransition = transition;
  });
  const leaving = () => ({ pose: { opacity: 0 }, timing: shownTransition });
</script>

<div class="split-divider" in:presence={{ pose: { opacity: 0 }, timing: transition }} out:liftOut={leaving()}>
  {#if shows}
    <!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
    <div
      class={["split-divider-handle", active && "active"]}
      style:width="{splitMetrics.handleHitWidth}px"
      style:left="{(splitMetrics.gap - splitMetrics.handleHitWidth) / 2}px"
      role="separator"
      aria-orientation="vertical"
      aria-label="Resize Split View Columns"
      aria-valuetext={`Divider ${index + 1}`}
      tabindex={interactive ? 0 : -1}
      onpointerdown={(event) => {
        if (!interactive || event.button !== 0 || drag) return;
        event.preventDefault();
        event.stopPropagation();
        event.currentTarget.setPointerCapture(event.pointerId);
        const pointer = holdPointer();
        const pages = holdLiveResize();
        drag = {
          pointerId: event.pointerId, x: event.clientX, baseline: shares,
          release: () => {
            pointer();
            pages();
          },
        };
        active = true;
      }}
      onpointermove={(event) => {
        const begun = drag;
        if (begun && event.pointerId === begun.pointerId) resize(event.clientX - begun.x, begun.baseline);
      }}
      onpointerup={finish}
      onpointercancel={finish}
      onlostpointercapture={finish}
      onkeydown={(event) => {
        const step = event.key === "ArrowRight" ? splitMetrics.keyboardStep : event.key === "ArrowLeft" ? -splitMetrics.keyboardStep : 0;
        if (!interactive || step === 0) return;
        event.preventDefault();
        resize(step, shares);
        // Each step is its own resize, measured from the row on screen.
        requestAnimationFrame(() => commit(shares));
      }}
    >
      <span class="split-divider-indicator" aria-hidden="true"></span>
    </div>
  {/if}
</div>
