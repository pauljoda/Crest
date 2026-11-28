<script lang="ts" module>
  /** How long the list rests after a scroll before its indicator goes, as the Mac's idle deadline. */
  const idleAfter = 600;
  /** The Mac's animated step down: 85% of the list's height in 0.22 s, eased in and out. */
  const step = { share: 0.85, duration: 220 };

  interface ScrollMetrics {
    readonly offset: number;
    readonly content: number;
    readonly viewport: number;
  }
</script>

<script lang="ts">
  import { untrack } from "svelte";

  import { reducesMotion } from "../motion";
  import SymbolIcon from "../SymbolIcon.svelte";

  /**
   * SidebarScrollAffordance on a pointer shell: the tab list hides its own
   * scroll bar, shows a thin indicator at its trailing edge only while it
   * scrolls, and, while rows run past its bottom and it rests, a round
   * "Show more tabs" button over its bottom edge that scrolls most of a page
   * further. A lift in flight hides the button. It draws over the list that
   * shares its parent, which clips it.
   */
  let { dragging }: { dragging: boolean } = $props();

  let layer = $state<HTMLDivElement | null>(null);
  let metrics = $state.raw<ScrollMetrics>({ offset: 0, content: 0, viewport: 0 });
  let scrolling = $state(false);
  const list = () => layer?.parentElement?.querySelector<HTMLElement>(":scope > .tab-list") ?? null;
  const measure = () => {
    const element = list();
    if (!element) return;
    const next = { offset: element.scrollTop, content: element.scrollHeight, viewport: element.clientHeight };
    const current = metrics;
    if (current.offset !== next.offset || current.content !== next.content || current.viewport !== next.viewport) metrics = next;
  };

  $effect(() => {
    const element = list();
    if (!element) return;
    return untrack(() => {
      const sized = () => ({ offset: element.scrollTop, content: element.scrollHeight, viewport: element.clientHeight });
      let last = sized();
      let idle = 0;
      const onScroll = () => {
        // A list that only grew or shrank moved without anyone scrolling it.
        const moved = element.scrollHeight === last.content && element.clientHeight === last.viewport;
        last = sized();
        if (moved) {
          scrolling = true;
          clearTimeout(idle);
          idle = window.setTimeout(() => {
            scrolling = false;
          }, idleAfter);
        }
        measure();
      };
      // A list that grew or shrank where it stands is the size the next scroll
      // starts from; one the change moved keeps the size before, so that move
      // is not taken for a scroll.
      const laidOut = () => {
        if (element.scrollTop === last.offset) last = sized();
        measure();
      };
      element.addEventListener("scroll", onScroll, { passive: true });
      const observer = new ResizeObserver(laidOut);
      observer.observe(element);
      // Rows come and go with every change the sidebar draws, and a lift
      // hides and shows them: the list is measured as each change lands.
      const rows = new MutationObserver(laidOut);
      rows.observe(element, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
      measure();
      return () => {
        element.removeEventListener("scroll", onScroll);
        observer.disconnect();
        rows.disconnect();
        clearTimeout(idle);
      };
    });
  });

  const maximum = $derived(Math.max(0, metrics.content - metrics.viewport));
  const moreBelow = $derived(metrics.content > metrics.offset + metrics.viewport + 1);
  const showsBubble = $derived(moreBelow && !scrolling && !dragging);
  const track = $derived(Math.max(0, metrics.viewport - 8));
  const thumb = $derived(Math.min(track, Math.max(24, track * metrics.viewport / Math.max(1, metrics.content))));
  const fraction = $derived(Math.min(1, Math.max(0, metrics.offset / Math.max(1, maximum))));

  const scrollDown = () => {
    const element = list();
    if (!element) return;
    const from = element.scrollTop;
    const to = Math.min(element.scrollHeight - element.clientHeight, from + element.clientHeight * step.share);
    if (reducesMotion()) {
      element.scrollTop = to;
      return;
    }
    const start = performance.now();
    const frame = (now: number) => {
      const t = Math.min(1, (now - start) / step.duration);
      const eased = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2;
      element.scrollTop = from + (to - from) * eased;
      if (t < 1) requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  };
</script>

<div bind:this={layer} class="sidebar-scroll-affordance" aria-hidden={!showsBubble || undefined}>
  <span class={`sidebar-scroll-indicator${scrolling && maximum > 1 ? " shows" : ""}`}
    style:height="{thumb}px" style:transform="translateY({4 + (track - thumb) * fraction}px)"></span>
  <button type="button" class={`sidebar-more-tabs${showsBubble ? " shows" : ""}`} aria-label="Show more tabs"
    data-testid="sidebar-more-tabs" tabindex={showsBubble ? 0 : -1} onclick={scrollDown}>
    <span class="sidebar-more-tabs-bubble"><SymbolIcon name="arrow.down" size={11} strokeWidth={2.5} /></span>
  </button>
</div>
