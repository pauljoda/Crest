<script lang="ts" module>
  /** The arrow a hanging popover points with: its width, and how far its tip stands the panel from the anchor. */
  const popoverArrow = { width: 28, reach: 13 } as const;

  /** Which side of its anchor a hanging popover stands on. */
  type PopoverSide = "below" | "above" | "after" | "before";

  /** Where the arrow stands, `along` the panel's edge facing the anchor: its base just inside the edge, its tip 10.5 out. */
  function arrowPlace(side: PopoverSide, along: number, width: number) {
    const half = popoverArrow.width / 2;
    switch (side) {
      case "below": return { left: along - half, top: -10.5 };
      case "above": return { left: along - half, bottom: -10.5, transform: "rotate(180deg)" };
      case "after": return { left: -5 - half, top: along - 5.5, transform: "rotate(-90deg)" };
      case "before": return { left: width + 5 - half, top: along - 5.5, transform: "rotate(90deg)" };
    }
  }

  /** The arrow's tip, which the popover grows from. */
  function arrowOrigin(side: PopoverSide, along: number): string {
    switch (side) {
      case "below": return `${along}px -10px`;
      case "above": return `${along}px calc(100% + 10px)`;
      case "after": return `-10px ${along}px`;
      case "before": return `calc(100% + 10px) ${along}px`;
    }
  }

  /** A length in pixels, or nothing where there is none. */
  function px(value: number | undefined): string | undefined {
    return value === undefined ? undefined : `${value}px`;
  }
</script>

<script lang="ts">
  import { motion as tokens } from "@crest/design";
  import { type Snippet, untrack } from "svelte";

  import { portal } from "../../attachments";
  import { presence } from "../../motion";

  /**
   * A popover at `anchor`, as the Mac's crestPopover: past the anchor's
   * trailing side by default, or, at the bottom edge, hanging below it with its
   * arrow pointing up at the anchor's middle; where the window has no room
   * below, it goes above, and with no room above either, beside the anchor, as
   * NSPopover tries its other edges. It goes when the person presses anywhere
   * else, other than on `ignore`, such as the control that toggles it, or
   * presses Escape.
   */
  let { anchor, label, onClose, children, edge = "trailing", ignore = null, className }: {
    anchor: DOMRect;
    label: string;
    onClose: () => void;
    children?: Snippet;
    edge?: "trailing" | "bottom";
    ignore?: Element | null;
    className?: string;
  } = $props();

  let panel = $state<HTMLDivElement>();
  let place = $state<{ left: number; top: number; side?: PopoverSide; arrow?: number }>(
    untrack(() => ({ left: anchor.right + 10, top: anchor.top })),
  );
  $effect(() => {
    const at = anchor;
    const along = edge;
    untrack(() => {
      const element = panel;
      if (!element) return;
      const width = element.offsetWidth;
      const height = element.offsetHeight;
      if (along === "trailing") {
        place = { left: at.right + 10, top: Math.max(8, Math.min(at.top + at.height / 2 - height / 2, innerHeight - height - 8)) };
        return;
      }
      const margin = 8;
      const reach = popoverArrow.reach;
      const clamp = (value: number, low: number, high: number) => Math.max(low, Math.min(value, high));
      const middleX = at.left + at.width / 2;
      const middleY = at.top + at.height / 2;
      const left = clamp(middleX - width / 2, margin, innerWidth - width - margin);
      const top = clamp(middleY - height / 2, margin, innerHeight - height - margin);
      const end = popoverArrow.width / 2 + 16;
      const arrowX = clamp(middleX - left, end, width - end);
      const arrowY = clamp(middleY - top, end, height - end);
      if (at.bottom + reach + height <= innerHeight - margin) {
        place = { left, top: at.bottom + reach, side: "below", arrow: arrowX };
      } else if (at.top - reach - height >= margin) {
        place = { left, top: at.top - reach - height, side: "above", arrow: arrowX };
      } else if (at.right + reach + width <= innerWidth - margin) {
        place = { left: at.right + reach, top, side: "after", arrow: arrowY };
      } else if (at.left - reach - width >= margin) {
        place = { left: at.left - reach - width, top, side: "before", arrow: arrowY };
      } else {
        place = { left, top: Math.min(at.bottom + reach, innerHeight - height - margin), side: "below", arrow: arrowX };
      }
    });
  });
  $effect(() => {
    const close = onClose;
    const ignored = ignore;
    return untrack(() => {
      const away = (event: PointerEvent) => {
        if (!(event.target instanceof Node)) return close();
        if (panel?.contains(event.target) || ignored?.contains(event.target)) return;
        close();
      };
      const escape = (event: KeyboardEvent) => {
        if (event.key !== "Escape") return;
        event.stopPropagation();
        close();
      };
      window.addEventListener("pointerdown", away, true);
      window.addEventListener("keydown", escape, true);
      return () => {
        window.removeEventListener("pointerdown", away, true);
        window.removeEventListener("keydown", escape, true);
      };
    });
  });
  const hangs = $derived(edge === "bottom" && place.side !== undefined && place.arrow !== undefined);
  const arrow = $derived(hangs ? arrowPlace(place.side!, place.arrow!, panel?.offsetWidth ?? 0) : null);
</script>

<!-- It comes in as the Mac's popover does and goes at once, as the system popover crestPopover wraps does (D17). -->
<div bind:this={panel} class={["crest-popover", className]} role="dialog" aria-label={label}
  style:left="{place.left}px" style:top="{place.top}px"
  style:transform-origin={hangs ? arrowOrigin(place.side!, place.arrow!) : undefined}
  in:presence|global={{ pose: { opacity: 0, scale: 0.96 }, timing: tokens.floatingPane }}
  {@attach portal(() => document.querySelector(".browser-window") ?? document.body)}>
  {#if arrow}
    <svg class="crest-popover-arrow" width={popoverArrow.width} height="11" viewBox="0 0 28 11"
      style:left={px(arrow.left)} style:top={px(arrow.top)} style:bottom={px(arrow.bottom)} style:transform={arrow.transform}
      aria-hidden="true">
      <path d="M0 11c4 0 6.5-1.6 8.6-3.7l3.6-3.6a2.5 2.5 0 0 1 3.6 0l3.6 3.6C21.5 9.4 24 11 28 11z" fill="currentColor" />
    </svg>
  {/if}
  {@render children?.()}
</div>
