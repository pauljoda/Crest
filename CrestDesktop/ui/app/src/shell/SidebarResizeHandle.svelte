<script lang="ts" module>
  /** The handle's grip, its indicator, and how far an arrow key moves it, as the Mac's BrowserSidebarResizeHandleMetrics. */
  const handleMetrics = { hitWidth: 16, step: 20 } as const;
</script>

<script lang="ts">
  import { sidebarOnRight } from "../appearance.svelte";
  import { holdLiveResize } from "./PageCard.svelte";
  import { holdPointer } from "./pointer-hold";
  import { clampedSidebarWidth, sidebarWidths } from "./sidebar-layout";

  /**
   * The sidebar's resize handle, as the Mac's BrowserSidebarResizeHandle: a
   * grip at the sidebar's edge that a drag widens or narrows within its
   * bounds, the page following live, showing a thin bar while it moves. The
   * resize settles when the drag ends however it ends, or when the handle goes
   * under it. Its arrow keys step the width, as the Mac's adjustable action does.
   */
  let { grip = $bindable(null), width, center, floating, onResize, onResizeEnded, onLeave }: {
    /** The grip, for the slot to tell whether the pointer is on the card's edge. */
    grip?: HTMLDivElement | null;
    width: number;
    /** Where the grip's middle stands, as a CSS length from the window's leading edge. */
    center: string;
    floating: boolean;
    onResize: (width: number) => void;
    onResizeEnded: (width: number) => void;
    onLeave: (event: MouseEvent) => void;
  } = $props();

  let drag: {
    readonly pointerId: number;
    readonly x: number;
    readonly width: number;
    /** Lets go of the pointer and of the pages, which the drag resizes each move. */
    readonly release: () => void;
  } | null = null;
  // The width the handle last reached, which follows the width it is given.
  let latest = 0;
  $effect.pre(() => {
    latest = width;
  });
  let active = $state(false);
  // Only the pointer that began the drag ends it.
  const finish = (event: PointerEvent) => {
    const begun = drag;
    if (!begun || event.pointerId !== begun.pointerId) return;
    drag = null;
    begun.release();
    active = false;
    onResizeEnded(latest);
  };
  // A handle that goes mid-drag, as when the sidebar is put away, still settles the width it reached.
  $effect(() => () => {
    const begun = drag;
    if (!begun) return;
    begun.release();
    onResizeEnded(latest);
  });
  const resize = (next: number) => {
    latest = clampedSidebarWidth(next);
    onResize(latest);
  };
</script>

<!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
<div
  bind:this={grip}
  class={`sidebar-resize-handle${active ? " active" : ""}${floating ? " floating" : ""}`}
  style:--handle-edge="calc({center} - {handleMetrics.hitWidth / 2}px)"
  style:width="{handleMetrics.hitWidth}px"
  role="separator"
  aria-orientation="vertical"
  aria-label="Resize Sidebar"
  aria-valuenow={Math.round(width)}
  aria-valuemin={sidebarWidths.minimum}
  aria-valuemax={sidebarWidths.maximum}
  tabindex="0"
  onpointerdown={(event) => {
    if (event.button !== 0 || drag) return;
    // The handle moves as the width changes, so the drag is measured from where it began.
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    const pointer = holdPointer();
    const pages = holdLiveResize();
    drag = {
      pointerId: event.pointerId, x: event.clientX, width,
      release: () => {
        pointer();
        pages();
      },
    };
    active = true;
  }}
  onpointermove={(event) => {
    const begun = drag;
    if (begun && event.pointerId === begun.pointerId) resize(begun.width + (event.clientX - begun.x) * (sidebarOnRight.current ? -1 : 1));
  }}
  onpointerup={finish}
  onpointercancel={finish}
  onlostpointercapture={finish}
  onkeydown={(event) => {
    const step = event.key === "ArrowRight" ? handleMetrics.step : event.key === "ArrowLeft" ? -handleMetrics.step : 0;
    if (step === 0) return;
    event.preventDefault();
    resize(width + (sidebarOnRight.current ? -step : step));
    onResizeEnded(latest);
  }}
  onmouseleave={onLeave}
>
  <span class="sidebar-resize-indicator" aria-hidden="true"></span>
</div>
