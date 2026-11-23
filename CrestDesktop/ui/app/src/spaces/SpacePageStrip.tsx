import type { SpaceState } from "@crest/contracts";
import { type ReactElement, type RefObject, useEffect, useLayoutEffect, useRef } from "react";

import {
  animateSettle, applyLeafStyle, type LeafStyle, type PagerFrame, placedIndex, spacePager, SpaceSwipe, stopSettle, touchpadPhases,
  useSpacePager,
} from "./space-pager";

/**
 * The sidebar's Space pages side by side, as the Mac's SpacePagerViewport
 * holds them: the shown Space's page, live, and while a slide or a swipe
 * moves the strip, the page it moves to or from, drawn still. Every page
 * moves a whole sidebar width per Space on the pager's clock, and none takes
 * the pointer until the strip comes to rest. The shown Space's neighbours wait
 * drawn beneath it, unseen, so a slide moves pages the compositor already
 * holds.
 */
export function SpacePageStrip({ spaces, liveId, gestureArea, render }: {
  spaces: readonly SpaceState[];
  /** The Space the window shows, whose page is the live one. */
  liveId: string;
  /** Where a swipe moves the strip: the pages and the chrome above them. */
  gestureArea: RefObject<HTMLElement | null>;
  render: (space: SpaceState, live: boolean) => ReactElement;
}) {
  const frame = useSpacePager();
  const strip = useRef<HTMLDivElement>(null);
  const pages = useRef(new Map<string, HTMLDivElement>());
  const moving = frame.phase !== "idle";
  // The shown Space's page always, beside the ones the pager has on screen and its neighbours.
  const shown = [...new Set([...frame.pages, liveId, ...frame.prepared])]
    .map((id) => spaces.find((space) => space.id === id))
    .filter((space): space is SpaceState => !!space);

  useLayoutEffect(() => {
    const element = strip.current;
    if (!element) return;
    const measure = () => spacePager.setWidth(element.getBoundingClientRect().width);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  // Each frame moves the pages, without drawing them again.
  const shownIds = shown.map((space) => space.id).join();
  useLayoutEffect(() => spacePager.subscribeFrames((current) => place(current, pages.current, liveId)), [liveId, shownIds]);

  // A horizontal swipe over the sidebar moves the strip; the wheel's other motion scrolls as ever.
  useEffect(() => {
    const area = gestureArea.current;
    if (!area) return;
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
  }, [gestureArea]);

  return (
    <div ref={strip} className={`space-pages${moving ? " moving" : ""}`}>
      {shown.map((space) => {
        const live = space.id === liveId;
        return (
          <div
            key={space.id}
            ref={(element) => {
              if (element) pages.current.set(space.id, element);
              else pages.current.delete(space.id);
            }}
            className="space-page"
            data-space-page={space.id}
            // A page takes input only at rest, and only the shown Space's.
            inert={!live || moving}
            aria-hidden={!live || undefined}
          >
            {render(space, live)}
          </div>
        );
      })}
    </div>
  );
}

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
