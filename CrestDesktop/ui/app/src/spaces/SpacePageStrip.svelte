<script lang="ts" module>
  import type { SpaceState } from "@crest/contracts";

  import {
    animateSettle, applyLeafStyle, type LeafStyle, type PagerFrame, placedIndex, spacePager, stopSettle,
  } from "./space-pager";

  /** Where a page stands at the pager's frame: its place in the strip's order less the position, in widths. */
  function pageStyle(id: string, frame: PagerFrame, liveId: string): LeafStyle {
    const count = frame.order.length;
    const index = frame.order.indexOf(id);
    // A Space beside the shown one waits drawn, in place and unseen, on a layer
    // of its own, for a slide to take it up. It takes no input, being inert.
    if (id !== liveId && id !== frame.originId && !frame.pages.includes(id) && frame.prepared.includes(id)) {
      return { visibility: "", opacity: "0", transform: "", willChange: "transform, opacity" };
    }
    // A shown Space the pager hasn't taken up yet waits off the strip, out of sight.
    if (index < 0 || (frame.phase === "idle" && id !== frame.originId && id !== liveId)) return { visibility: "hidden" };
    const offset = frame.phase === "idle" ? (id === frame.originId ? 0 : 1) : placedIndex(index, frame.position, count) - frame.position;
    return {
      visibility: Math.abs(offset) >= 1 ? "hidden" : "",
      transform: offset === 0 ? "" : `translateX(${offset * 100}%)`,
      // A moving page gets a compositor layer of its own. At rest it gives the
      // layer up, so what sits fixed in it (a lifted row, the lists' fan) keeps
      // the window.
      willChange: frame.phase === "idle" ? "" : "transform",
    };
  }

  /** Places each page: a settle runs on the compositor, while a swipe and rest are written each frame. */
  function place(frame: PagerFrame, pages: ReadonlyMap<string, HTMLDivElement>, liveId: string) {
    const settle = frame.phase === "settling" ? spacePager.settle : null;
    for (const [id, element] of pages) {
      if (settle) {
        animateSettle(element, settle, (at) => pageStyle(id, at, liveId));
        continue;
      }
      stopSettle(element);
      applyLeafStyle(element, pageStyle(id, frame, liveId));
    }
  }
</script>

<script lang="ts">
  import { type Snippet, untrack } from "svelte";
  import type { Attachment } from "svelte/attachments";

  import { readsLight } from "../branding";
  import { SpaceSwipe, touchpadPhases, useSpacePager } from "./space-pager";

  /**
   * The sidebar's Space pages side by side, as the Mac's SpacePagerViewport
   * holds them: the shown Space's page, live, and while a slide or a swipe
   * moves the strip, the page it moves to or from, drawn still. Every page
   * moves a whole sidebar width per Space on the pager's clock, and none takes
   * the pointer until the strip comes to rest. The shown Space's neighbours wait
   * drawn beneath it, unseen, so a slide moves pages the compositor already
   * holds.
   */
  let { spaces, liveId, gestureArea, render }: {
    spaces: readonly SpaceState[];
    /** The Space the window shows, whose page is the live one. */
    liveId: string;
    /**
     * Where a swipe moves the strip: the pages and the chrome above them. The
     * element as it is bound (`bind:this` to a `$state` variable), so the strip
     * hears of it once it stands.
     */
    gestureArea: HTMLElement | null | undefined;
    render: Snippet<[space: SpaceState, live: boolean]>;
  } = $props();

  const frame = $derived(useSpacePager());
  let strip: HTMLDivElement | undefined;
  const pages = new Map<string, HTMLDivElement>();
  const moving = $derived(frame.phase !== "idle");
  // The shown Space's page always, beside the ones the pager has on screen and its neighbours.
  const shown = $derived([...new Set([...frame.pages, liveId, ...frame.prepared])]
    .map((id) => spaces.find((space) => space.id === id))
    .filter((space): space is SpaceState => !!space));

  $effect(() => {
    const element = strip;
    if (!element) return;
    const measure = () => spacePager.setWidth(element.getBoundingClientRect().width);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  });

  // Each frame moves the pages, without drawing them again.
  const shownIds = $derived(shown.map((space) => space.id).join());
  $effect(() => {
    const live = liveId;
    void shownIds;
    return untrack(() => spacePager.subscribeFrames((current) => place(current, pages, live)));
  });

  // A horizontal swipe over the sidebar moves the strip; the wheel's other motion scrolls as ever.
  $effect(() => {
    const area = gestureArea;
    if (!area) return;
    return untrack(() => {
      // The switcher's own strip scrolls its crests; everywhere else in the area a swipe moves Spaces.
      const swipes = (target: Element | null) => !!target && area.contains(target) && !target.closest(".space-strip");
      const swipe = new SpaceSwipe((x, y) => swipes(document.elementFromPoint(x, y)));
      const onWheel = (event: WheelEvent) => {
        if (event.ctrlKey || !swipes(event.target instanceof Element ? event.target : null)) return;
        if (swipe.handle(event)) event.preventDefault();
      };
      area.addEventListener("wheel", onWheel, { passive: false });
      const stopPhases = touchpadPhases.subscribe((wheel) => swipe.phased(wheel));
      return () => {
        area.removeEventListener("wheel", onWheel);
        stopPhases();
        swipe.dispose();
      };
    });
  });

  /** Keeps each page in `pages` while it stands. */
  const page = (id: string): Attachment<HTMLDivElement> => (element) => untrack(() => {
    pages.set(id, element);
    return () => {
      pages.delete(id);
    };
  });
</script>

<div bind:this={strip} class={["space-pages", moving && "moving"]}>
  {#each shown as space (space.id)}
    {@const live = space.id === liveId}
    <!-- Each page wears its own Space's look, as it slides past the others. A page takes input only at rest, and only the shown Space's. -->
    <div
      {@attach page(space.id)}
      class={["space-page", readsLight(space.settings.look) ? "reads-light" : "reads-dark"]}
      data-space-page={space.id}
      inert={!live || moving}
      aria-hidden={!live || undefined}
    >
      {@render render(space, live)}
    </div>
  {/each}
</div>
