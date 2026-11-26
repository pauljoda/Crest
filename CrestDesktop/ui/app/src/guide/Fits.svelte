<script lang="ts">
  import type { Snippet } from "svelte";

  /**
   * SwiftUI's ViewThatFits over a row and a stack: the row where it fits on
   * one line, the stack where it doesn't, decided again as the room changes.
   * An unseen copy of the row, at its own width, says how much it needs.
   */
  let { wide, narrow }: { wide: Snippet; narrow: Snippet } = $props();

  let box = $state<HTMLDivElement>();
  let probe = $state<HTMLDivElement>();
  let fits = $state(true);
  $effect(() => {
    const room = box;
    const needs = probe;
    if (!room || !needs) return;
    const check = () => {
      fits = needs.scrollWidth <= room.clientWidth + 0.5;
    };
    check();
    // The room changes with the guide's width; what the row needs, as its faces load.
    const observer = new ResizeObserver(check);
    observer.observe(room);
    observer.observe(needs);
    return () => observer.disconnect();
  });
</script>

<div bind:this={box} class="guide-fits">
  {#if fits}
    <div class="guide-actions row">{@render wide()}</div>
  {:else}
    <div class="guide-actions stack">{@render narrow()}</div>
  {/if}
  <div bind:this={probe} class="guide-actions row guide-fits-probe" aria-hidden="true" inert>{@render wide()}</div>
</div>
