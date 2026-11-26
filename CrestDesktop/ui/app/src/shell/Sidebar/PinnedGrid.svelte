<script lang="ts">
  import type { Snippet } from "svelte";

  import { pinCapacity, pinColumns } from "../sidebar-layout";

  /**
   * The pinned tiles in the Mac's PinnedTabGridLayout: at most four to a row,
   * fewer where the sidebar has no room for four tiles of the Mac's narrowest,
   * and the rows balanced, so one tile spans the sidebar, five sit three over
   * two, and every tile shares its row's width.
   */
  let { count, children, className, ...rest }: {
    count: number;
    children?: Snippet;
    className: string;
    "data-list-section": string;
    "data-list-folder": string;
  } = $props();

  let grid = $state<HTMLDivElement | null>(null);
  // Only a change in how many tiles fit redraws the grid, not every step of a resize.
  let capacity = $state(4);
  $effect(() => {
    const element = grid;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => {
      capacity = pinCapacity(entry.contentRect.width);
    });
    observer.observe(element);
    return () => observer.disconnect();
  });
</script>

<div bind:this={grid} class={className} {...rest} style:--pin-columns={pinColumns(count, capacity)}>
  {@render children?.()}
</div>
