import type { TabState } from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion } from "motion/react";
import { useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore } from "react";

import type { Session } from "../boot";
import { type TabPictures, useTabPictures } from "../switcher/tab-pictures";
import { TabIcon } from "./Sidebar";

/** BrowserTabPreviewState's timing, in milliseconds. */
const timing = { rest: 500, move: 120, aim: 350, leave: 150 };

/** The tab a card shows, and the row it stands beside. */
interface Shown {
  readonly tabId: string;
  readonly row: DOMRect;
}

type Point = { readonly x: number; readonly y: number };

/**
 * The Mac's BrowserTabPreviewState: which tab's card shows, from where the
 * pointer rests. A row rested on for half a second shows its tab's card;
 * while a card shows, another row takes it after 120 ms, or 350 ms while the
 * pointer crosses rows on its way into the card; the card goes 150 ms after
 * the pointer leaves both the row and the card. A card put away by a key, a
 * press or a scroll stays away until the pointer enters another row.
 */
class TabPreviewState {
  #shown: Shown | null = null;
  #listeners = new Set<() => void>();
  #timer = 0;
  #resting: string | null = null;
  #dismissed: string | null = null;
  #onCard = false;
  /** Whether the pointer has gone onto the page since it last rested on a row or the card. */
  #onPage = false;
  /** Where the pointer left the shown row, for telling a crossing on the way into the card. */
  #leftAt: Point | null = null;
  enabled = true;

  get shown(): Shown | null {
    return this.#shown;
  }

  /** Whether a card shows, which the page beside the sidebar is covered for. */
  get covers(): boolean {
    return this.#shown !== null;
  }

  /**
   * The pointer moved onto the page beside the sidebar, which tells the
   * interface nothing of the pointer itself: it left the row it rested on.
   */
  pointerOnPage(pointer: Point) {
    // The first move says it; the moves after it only wait out the leave.
    if (this.#onPage) return;
    this.#onPage = true;
    if (this.#resting) this.leave(this.#resting, pointer);
    this.#onCard = false;
    clearTimeout(this.#timer);
    this.#show(null);
  }

  subscribe(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  /** The pointer came to rest on a tab's row. */
  rest(tabId: string, row: HTMLElement, pointer: Point) {
    if (!this.enabled) return;
    if (this.#resting === tabId) return;
    if (this.#dismissed && this.#dismissed !== tabId) this.#dismissed = null;
    if (this.#dismissed === tabId) return;
    this.#resting = tabId;
    this.#onPage = false;
    this.#notify();
    clearTimeout(this.#timer);
    const delay = !this.#shown ? timing.rest : this.#aimsAtCard(pointer) ? timing.aim : timing.move;
    this.#timer = window.setTimeout(() => {
      if (this.#resting !== tabId || !row.isConnected) return;
      this.#show({ tabId, row: row.getBoundingClientRect() });
    }, delay);
  }

  /** The pointer left a tab's row. */
  leave(tabId: string, pointer: Point) {
    if (this.#resting === tabId) {
      this.#resting = null;
      this.#notify();
    }
    if (this.#shown?.tabId === tabId) this.#leftAt = pointer;
    this.#scheduleLeave();
  }

  enterCard() {
    this.#onCard = true;
    this.#onPage = false;
    clearTimeout(this.#timer);
  }

  leaveCard() {
    this.#onCard = false;
    this.#scheduleLeave();
  }

  /** Puts the card away until the pointer enters another row. */
  dismiss() {
    if (!this.#shown && !this.#resting) return;
    this.#dismissed = this.#shown?.tabId ?? this.#resting;
    this.#resting = null;
    clearTimeout(this.#timer);
    this.#show(null);
  }

  #scheduleLeave() {
    clearTimeout(this.#timer);
    this.#timer = window.setTimeout(() => {
      if (!this.#onCard && !this.#resting) this.#show(null);
    }, timing.leave);
  }

  #show(next: Shown | null) {
    if (next === null) {
      this.#onCard = false;
      this.#onPage = false;
    }
    this.#shown = next;
    this.#notify();
  }

  #notify() {
    this.#version++;
    for (const listener of this.#listeners) listener();
  }

  #version = 0;

  get version(): number {
    return this.#version;
  }

  /** Whether the pointer is inside the triangle from where it left the row to the card's near edge. */
  #aimsAtCard(pointer: Point): boolean {
    const card = document.querySelector(".tab-preview")?.getBoundingClientRect();
    const from = this.#leftAt;
    if (!card || !from) return false;
    const a = from;
    const b = { x: card.left, y: card.top };
    const c = { x: card.left, y: card.bottom };
    const side = (p: Point, q: Point, r: Point) => (p.x - r.x) * (q.y - r.y) - (q.x - r.x) * (p.y - r.y);
    const d1 = side(pointer, a, b);
    const d2 = side(pointer, b, c);
    const d3 = side(pointer, c, a);
    return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0));
  }
}

export const tabPreview = new TabPreviewState();

/** Whether the person shows previews of tabs on hover, as Settings › Appearance keeps it on this device. */
export function showsTabPreviews(): boolean {
  try {
    return localStorage.getItem("crest.appearance.hover-preview.tabs") !== "false";
  } catch {
    return true;
  }
}

/** The handlers a tab row gives the pointer, which tell the card where it rests. */
export function previewHandlers(tabId: string) {
  return {
    onPointerEnter: (event: React.PointerEvent<HTMLElement>) =>
      tabPreview.rest(tabId, event.currentTarget, { x: event.clientX, y: event.clientY }),
    onPointerLeave: (event: React.PointerEvent<HTMLElement>) => tabPreview.leave(tabId, { x: event.clientX, y: event.clientY }),
  };
}

/** BrowserTabPreviewSurface and BrowserTabPreviewCard's measures. */
const card = { width: 280, padding: 8, gap: 8, margin: 8, rise: 6, pictureHeight: 168, estimatedHeight: 220 };

/**
 * The Mac's BrowserTabPreviewLayer: the card of the tab the pointer rests on,
 * leaning against the sidebar's page edge with its top a little above the
 * row's, kept inside the window: the tab's icon, title and site, and the
 * last picture the window took of its page. It grows from the row's side,
 * fades away, and moves between rows at once; any key, press or scroll away
 * from it, or the window going to the background, puts it away.
 */
export function TabPreviewLayer({ session, tabs, pagesByTab, pictures, enabled }: {
  session: Session;
  tabs: ReadonlyMap<string, TabState>;
  pagesByTab: ReadonlyMap<string, string>;
  pictures: TabPictures;
  /** Whether cards may show: the sidebar shows, no palette covers the window, and the person keeps previews on. */
  enabled: boolean;
}) {
  useTabPictures(pictures);
  useSyncExternalStore((listener) => tabPreview.subscribe(listener), () => tabPreview.version);
  const shown = tabPreview.shown;
  tabPreview.enabled = enabled;
  useEffect(() => {
    if (!enabled) tabPreview.dismiss();
  }, [enabled]);
  useEffect(() => {
    const dismissOutside = (event: Event) => {
      if (event.target instanceof Element && event.target.closest(".tab-preview")) return;
      tabPreview.dismiss();
    };
    const dismiss = () => tabPreview.dismiss();
    const key = (event: KeyboardEvent) => {
      // Arrow keys move the selection the card follows; everything else puts it away.
      if (!event.key.startsWith("Arrow")) tabPreview.dismiss();
    };
    window.addEventListener("pointerdown", dismissOutside, true);
    window.addEventListener("wheel", dismissOutside, { capture: true, passive: true });
    window.addEventListener("keydown", key, true);
    window.addEventListener("blur", dismiss);
    return () => {
      window.removeEventListener("pointerdown", dismissOutside, true);
      window.removeEventListener("wheel", dismissOutside, { capture: true } as EventListenerOptions);
      window.removeEventListener("keydown", key, true);
      window.removeEventListener("blur", dismiss);
    };
  }, []);
  const tab = shown ? tabs.get(shown.tabId) : undefined;
  // A page tells the interface nothing of the pointer over it, so while a
  // card shows, the page area beside the sidebar is covered, and the
  // pointer's first move there is its leaving the row; the cover goes with
  // the card, before a click.
  const area = shown ? document.querySelector(".space-content")?.getBoundingClientRect() : undefined;
  const sidebarEdge = document.querySelector(".sidebar")?.getBoundingClientRect().right ?? 0;
  return (
    <div className="tab-preview-layer" aria-hidden>
      {enabled && tabPreview.covers && area && (
        <div className="tab-preview-cover"
          style={{ left: Math.max(area.left, sidebarEdge), top: area.top, width: area.right - Math.max(area.left, sidebarEdge), height: area.height }}
          onPointerMove={(event) => tabPreview.pointerOnPage({ x: event.clientX, y: event.clientY })}
          onPointerDown={() => tabPreview.dismiss()} />
      )}
      <AnimatePresence>
        {shown && tab && (
          <PreviewCard key="card" session={session} tab={tab} row={shown.row} pageId={pagesByTab.get(tab.id) ?? null}
            picture={pictures.picture(tab.id)} />
        )}
      </AnimatePresence>
    </div>
  );
}

function PreviewCard({ session, tab, row, pageId, picture }: {
  session: Session;
  tab: TabState;
  row: DOMRect;
  pageId: string | null;
  picture: string | null;
}) {
  const element = useRef<HTMLDivElement>(null);
  const [height, setHeight] = useState(card.estimatedHeight);
  useLayoutEffect(() => {
    if (element.current) setHeight(element.current.offsetHeight);
  });
  const sidebar = document.querySelector(".sidebar")?.getBoundingClientRect();
  const left = Math.min((sidebar?.right ?? row.right) + card.gap, innerWidth - card.width - card.margin);
  const top = Math.max(card.margin, Math.min(row.top - card.rise, innerHeight - height - card.margin));
  // It grows from the row's side, at the row's middle.
  const origin = `0px ${row.top + row.height / 2 - top}px`;
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const domain = siteOf(tab.url);
  return (
    <motion.div ref={element} className="tab-preview" style={{ left, top, transformOrigin: origin }}
      initial={reduce ? { opacity: 0 } : { opacity: 0, scale: 0.2 }} animate={{ opacity: 1, scale: 1 }}
      exit={{ opacity: 0, transition: tokens.hover }}
      transition={reduce ? tokens.hover : { type: "spring", visualDuration: 0.3, bounce: 0.12 }}
      onPointerEnter={() => tabPreview.enterCard()} onPointerLeave={() => tabPreview.leaveCard()}>
      <div className="tab-preview-header">
        <TabIcon session={session} tab={tab} pageId={pageId} size={16} />
        <div className="tab-preview-text">
          <span className="tab-preview-title">{tab.displayTitle}</span>
          {domain && <span className="tab-preview-site">{domain}</span>}
        </div>
      </div>
      {picture && <PreviewPicture src={picture} />}
    </motion.div>
  );
}

/** The page's last picture, as wide as the card allows and no taller than 168, its top kept. */
function PreviewPicture({ src }: { src: string }) {
  const [aspect, setAspect] = useState(0.75);
  const width = card.width - card.padding * 2;
  return (
    <img className="tab-preview-picture" src={src} alt="" style={{ height: Math.min(width * aspect, card.pictureHeight) }}
      onLoad={(event) => {
        const image = event.currentTarget;
        if (image.naturalWidth > 0) setAspect(image.naturalHeight / image.naturalWidth);
      }} />
  );
}

/** The site a tab's address names, without its scheme or a leading www. */
function siteOf(url: string | null): string | null {
  if (!url) return null;
  try {
    const host = new URL(url).hostname;
    return host ? host.replace(/^www\./, "") : null;
  } catch {
    return null;
  }
}
