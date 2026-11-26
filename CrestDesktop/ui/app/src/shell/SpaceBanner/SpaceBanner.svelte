<script lang="ts" module>
  import {
    animateSettle, applyLeafStyle, type LeafStyle, type PagerFrame, placedIndex, spacePager, stopSettle,
  } from "../../spaces/space-pager";

  /** A banner's opacity at the pager's position: clamp(position − index + 1), stacked by its place in the strip. */
  function bannerStyle(id: string, frame: PagerFrame, spaceId: string): LeafStyle {
    const count = frame.order.length;
    const index = frame.order.indexOf(id);
    if (frame.phase === "idle" || index < 0) {
      // At rest only the Space shown; one the pager hasn't taken up yet waits unseen.
      const resting = frame.phase === "idle" && frame.originId ? frame.originId : spaceId;
      return { opacity: id === resting ? "1" : "0", zIndex: id === resting ? "1" : "0" };
    }
    // A neighbour the slide doesn't take up stays unseen beneath it.
    if (!frame.pages.includes(id)) return { opacity: "0", zIndex: "0" };
    const placed = placedIndex(index, frame.position, count);
    return { zIndex: `${placed + count + 1}`, opacity: `${Math.min(1, Math.max(0, frame.position - placed + 1))}` };
  }

  /** Blends the banners: a settle on the compositor, a swipe and rest each frame. */
  function blend(frame: PagerFrame, layers: ReadonlyMap<string, HTMLDivElement>, spaceId: string) {
    const settle = frame.phase === "settling" ? spacePager.settle : null;
    for (const [id, element] of layers) {
      if (settle) {
        animateSettle(element, settle, (at) => bannerStyle(id, at, spaceId));
        continue;
      }
      stopSettle(element);
      applyLeafStyle(element, bannerStyle(id, frame, spaceId));
    }
  }

  /** The size `element` lays out at, followed as it changes; null until it is measured. */
  function useElementSize(element: () => HTMLElement | undefined): {
    readonly current: { width: number; height: number } | null;
  } {
    let size = $state.raw<{ width: number; height: number } | null>(null);
    $effect(() => {
      const target = element();
      if (!target) return;
      const observer = new ResizeObserver(([entry]) => {
        const { width, height } = entry.contentRect;
        if (size?.width !== width || size.height !== height) size = { width, height };
      });
      observer.observe(target);
      return () => observer.disconnect();
    });
    return {
      get current() {
        return size;
      },
    };
  }
</script>

<script lang="ts">
  import type { SpaceState } from "@crest/contracts";
  import type { Attachment } from "svelte/attachments";
  import { untrack } from "svelte";

  import { useSpacePager } from "../../spaces/space-pager";
  import BannerLayers from "./BannerLayers.svelte";

  /**
   * The Spaces' banners behind the window, drawn as the Mac draws each
   * (BrowserSpaceBannerBackground): the window's background, the Space's
   * pattern or gradient at the look's strength, a fade that keeps the chrome
   * readable, and the look's grain. As the Space pager moves, they blend as the
   * Mac's SpaceBackdropBlend does: stacked in the strip's order, each fading in
   * over the one before it as the strip reaches it. The shown Space's
   * neighbours wait drawn beneath it, unseen, each on its layer, so a slide
   * fades in banners the compositor already holds.
   */
  let { spaces, spaceId }: { spaces: readonly SpaceState[]; spaceId: string } = $props();

  let frame: HTMLDivElement;
  const size = useElementSize(() => frame);
  const layers = new Map<string, HTMLDivElement>();
  const shown = $derived.by(() => {
    const pager = useSpacePager();
    return [...new Set([...pager.pages, spaceId, ...pager.prepared])]
      .map((id) => spaces.find((space) => space.id === id))
      .filter((space): space is SpaceState => !!space);
  });
  const shownIds = $derived(shown.map((space) => space.id).join());
  $effect(() => {
    const shownSpace = spaceId;
    void shownIds;
    return untrack(() => spacePager.subscribeFrames((current) => blend(current, layers, shownSpace)));
  });
  // Each layer joins the blend as it is drawn, at the pager's frame, which
  // the subscription above may have drawn before the layer was there.
  const layer = (id: string): Attachment<HTMLDivElement> => (element) => {
    layers.set(id, element);
    untrack(() => blend(spacePager.frame, new Map([[id, element]]), spaceId));
    return () => {
      layers.delete(id);
    };
  };
</script>

<div bind:this={frame} class="space-banner" aria-hidden="true">
  {#each shown as space (space.id)}
    {@const id = space.id}
    <div class="space-banner-layer" {@attach layer(id)}>
      {#if size.current}
        <BannerLayers branding={space.settings.look} width={size.current.width} height={size.current.height} />
      {/if}
    </div>
  {/each}
</div>
