import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";

import { Symbol } from "../symbols";

/** How long the list rests after a scroll before its indicator goes, as the Mac's idle deadline. */
const idleAfter = 600;
/** The Mac's animated step down: 85% of the list's height in 0.22 s, eased in and out. */
const step = { share: 0.85, duration: 220 };

interface ScrollMetrics {
  readonly offset: number;
  readonly content: number;
  readonly viewport: number;
}

/**
 * SidebarScrollAffordance on a pointer shell: the tab list hides its own
 * scroll bar, shows a thin indicator at its trailing edge only while it
 * scrolls, and, while rows run past its bottom and it rests, a round
 * "Show more tabs" button over its bottom edge that scrolls most of a page
 * further. A lift in flight hides the button. It draws over the list that
 * shares its parent, which clips it.
 */
export function SidebarScrollAffordance({ dragging }: { dragging: boolean }) {
  const layer = useRef<HTMLDivElement>(null);
  const [metrics, setMetrics] = useState<ScrollMetrics>({ offset: 0, content: 0, viewport: 0 });
  const [scrolling, setScrolling] = useState(false);
  const list = useCallback(() => layer.current?.parentElement?.querySelector<HTMLElement>(":scope > .tab-list") ?? null, []);
  const measure = useCallback(() => {
    const element = list();
    if (!element) return;
    const next = { offset: element.scrollTop, content: element.scrollHeight, viewport: element.clientHeight };
    setMetrics((current) => (current.offset === next.offset && current.content === next.content
      && current.viewport === next.viewport ? current : next));
  }, [list]);
  // Rows come and go with every change the sidebar draws.
  useLayoutEffect(measure);

  useEffect(() => {
    const element = list();
    if (!element) return;
    let last = { content: element.scrollHeight, viewport: element.clientHeight };
    let idle = 0;
    const onScroll = () => {
      // A list that only grew or shrank moved without anyone scrolling it.
      const moved = element.scrollHeight === last.content && element.clientHeight === last.viewport;
      last = { content: element.scrollHeight, viewport: element.clientHeight };
      if (moved) {
        setScrolling(true);
        clearTimeout(idle);
        idle = window.setTimeout(() => setScrolling(false), idleAfter);
      }
      measure();
    };
    element.addEventListener("scroll", onScroll, { passive: true });
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => {
      element.removeEventListener("scroll", onScroll);
      observer.disconnect();
      clearTimeout(idle);
    };
  }, [list, measure]);

  const maximum = Math.max(0, metrics.content - metrics.viewport);
  const moreBelow = metrics.content > metrics.offset + metrics.viewport + 1;
  const showsBubble = moreBelow && !scrolling && !dragging;
  const track = Math.max(0, metrics.viewport - 8);
  const thumb = Math.min(track, Math.max(24, track * metrics.viewport / Math.max(1, metrics.content)));
  const fraction = Math.min(1, Math.max(0, metrics.offset / Math.max(1, maximum)));

  const scrollDown = () => {
    const element = list();
    if (!element) return;
    const from = element.scrollTop;
    const to = Math.min(element.scrollHeight - element.clientHeight, from + element.clientHeight * step.share);
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
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

  return (
    <div ref={layer} className="sidebar-scroll-affordance" aria-hidden={!showsBubble || undefined}>
      <span className={`sidebar-scroll-indicator${scrolling && maximum > 1 ? " shows" : ""}`}
        style={{ height: thumb, transform: `translateY(${4 + (track - thumb) * fraction}px)` }} />
      <button type="button" className={`sidebar-more-tabs${showsBubble ? " shows" : ""}`} aria-label="Show more tabs"
        data-testid="sidebar-more-tabs" tabIndex={showsBubble ? 0 : -1} onClick={scrollDown}>
        <span className="sidebar-more-tabs-bubble"><Symbol name="arrow.down" size={11} strokeWidth={2.5} /></span>
      </button>
    </div>
  );
}
