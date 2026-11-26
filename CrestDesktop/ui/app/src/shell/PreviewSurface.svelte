<script lang="ts">
  import { sidebarOnRight } from "../appearance.svelte";
  import { entranceScale, motion } from "@crest/design";
  import type { Snippet } from "svelte";
  import { innerHeight, innerWidth } from "svelte/reactivity/window";

  import { presence, presentationPickup, reducesMotion } from "../motion";
  import type { PreviewState } from "./preview-state.svelte";

  let { state: preview, row, edge, parent, children }: {
    state: PreviewState; row: DOMRect; edge: number; parent?: PreviewState; children: Snippet;
  } = $props();
  let element = $state<HTMLDivElement>();
  let height = $state(220);
  const left = $derived(Math.max(8, Math.min(sidebarOnRight.current ? edge - 288 : edge + 8, (innerWidth.current ?? 0) - 288)));
  const top = $derived(Math.max(8, Math.min(row.top - 6, (innerHeight.current ?? 0) - height - 8)));
  $effect(() => {
    const card = element;
    preview.card = card;
    return () => { if (preview.card === card) preview.card = undefined; };
  });
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div bind:this={element} bind:offsetHeight={height} class="tab-preview" style:left="{left}px" style:top="{top}px"
  style:transform-origin="{sidebarOnRight.current ? '100%' : '0%'} {row.top + row.height / 2 - top}px"
  in:presence|global={{ pose: { opacity: 0, scale: entranceScale }, timing: reducesMotion() ? motion.hover : { ...motion.tabPreview, delay: presentationPickup.tabPreview / 1000 } }}
  out:presence|global={{ pose: { opacity: 0 }, timing: { ...motion.hover, delay: reducesMotion() ? 0 : presentationPickup.pointer / 1000 } }}
  onpointerenter={() => { parent?.enterCard(); preview.enterCard(); }}
  onpointerleave={() => { preview.leaveCard(); parent?.leaveCard(); }}>
  {@render children()}
</div>
