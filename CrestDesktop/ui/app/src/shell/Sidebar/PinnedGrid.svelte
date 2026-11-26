<script lang="ts">
  import type { Snippet } from "svelte";

  import { pinGap, pinLayout, stretchPins, tabScale } from "../../appearance.svelte";
  import { pinColumns } from "../sidebar-layout";

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

  let width = $state(0);
  const columns = $derived(pinColumns(count, width, tabScale(), pinGap(), pinLayout.current));
</script>

<div bind:clientWidth={width} class={className} class:stretch={stretchPins.current} {...rest} style:--pin-columns={columns}>
  {@render children?.()}
</div>
