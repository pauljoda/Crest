import { type RecentTabItem, RecentTabs, ShowTab, type SpaceState, type TabState } from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { motion } from "motion/react";
import { type PointerEvent as ReactPointerEvent, useCallback, useEffect, useRef, useState } from "react";

import type { Session } from "../boot";
import { TabIcon } from "../shell/Sidebar";
import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
import { type TabPictures, useTabPictures } from "./tab-pictures";

/** The modifiers the switcher's keys hold, whose release picks the highlighted tab. */
export interface SwitcherHold {
  readonly control: boolean;
  readonly shift: boolean;
  readonly alt: boolean;
}

/**
 * How a switcher began, which the window keeps from the first press on: the
 * window takes the keyboard for it at once, before the switcher draws, so a
 * quick release still arrives, and notes here what came before the switcher
 * could hear it.
 */
export interface SwitcherStart {
  /** The step the first press took. */
  readonly direction: 1 | -1;
  readonly hold: SwitcherHold;
  /** Further steps taken before the switcher drew. */
  steps: number;
  /** Whether the held keys were let go before the switcher drew. */
  released: boolean;
  /** Whether the keyboard went elsewhere before the switcher drew. */
  lost: boolean;
}

/** What the window passes on to a switcher while it is held. */
export interface SwitcherControls {
  /** Another press of the keys that opened it, or the other direction's, that the window heard. */
  step(direction: 1 | -1): void;
  keyDown(event: KeyboardEvent): void;
  keyUp(event: KeyboardEvent): void;
  /** The keyboard went elsewhere: a click away, or the window going to the background. */
  lostKeys(): void;
}

/** Whether a key coming up is one of the modifiers the switcher's keys hold. */
export function releasesHold(event: { readonly key: string }, hold: SwitcherHold): boolean {
  return (event.key === "Control" && hold.control) || (event.key === "Shift" && hold.shift) || (event.key === "Alt" && hold.alt);
}

/**
 * The Mac's recent-tab switcher: while the keys of Most Recent Tab are held,
 * a panel over the window shows the tabs the window showed lately, the one
 * it shows first, and each further press moves the highlight; letting the
 * keys go shows the highlighted one. A quick press goes straight to the tab
 * before last without the panel showing. The window gives the switcher the
 * keyboard while it lasts, so the release arrives; arrows, digits and Return
 * work as they do on the Mac, and Esc, a click outside, or the window going
 * to the background leave things as they were.
 */
export function RecentTabSwitcher({ session, spaces, pagesByTab, pictures, start, register, onEnd }: {
  session: Session;
  spaces: readonly SpaceState[];
  pagesByTab: ReadonlyMap<string, string>;
  pictures: TabPictures;
  start: SwitcherStart;
  register: (controls: SwitcherControls | null) => void;
  onEnd: () => void;
}) {
  useTabPictures(pictures);
  const { direction, hold } = start;
  const [items, setItems] = useState<readonly RecentTabItem[] | null>(null);
  const [index, setIndex] = useState(0);
  const [shown, setShown] = useState(false);
  const itemsNow = useRef(items);
  itemsNow.current = items;
  const indexNow = useRef(index);
  indexNow.current = index;
  const ended = useRef(false);
  // A release before the list arrives picks from the list once it does.
  const commitsWhenListed = useRef(false);

  const finish = useCallback((commits: boolean) => {
    if (ended.current) return;
    if (commits && !itemsNow.current) {
      commitsWhenListed.current = true;
      return;
    }
    ended.current = true;
    const list = itemsNow.current;
    const item = commits && list && indexNow.current > 0 ? list[indexNow.current] : undefined;
    if (item) void session.core.send(ShowTab({ windowId: session.windowId, spaceId: item.spaceId, tabId: item.focusedTabId })).catch(() => {});
    onEnd();
  }, [session, onEnd]);
  const highlight = useCallback((next: number) => {
    const count = itemsNow.current?.length ?? 0;
    if (count === 0) return;
    indexNow.current = ((next % count) + count) % count;
    setIndex(indexNow.current);
  }, []);
  // Steps that come before the list are counted from where the list starts.
  const earlySteps = useRef(0);
  const step = useCallback((by: 1 | -1) => {
    setShown(true);
    if (!itemsNow.current) earlySteps.current += by;
    else highlight(indexNow.current + by);
  }, [highlight]);

  /** Whether an event says the keys were let go without the switcher hearing it. */
  const releasedUnheard = (event: { ctrlKey: boolean; altKey: boolean }) =>
    (hold.control && !event.ctrlKey) || (hold.alt && !event.altKey);
  const keyDown = (event: KeyboardEvent) => {
    // A held modifier repeating says nothing new.
    if (event.key === "Control" || event.key === "Shift" || event.key === "Alt") return;
    // A key without the modifier the keys hold is a release that went
    // elsewhere; Shift only turns a step around.
    if (releasedUnheard(event)) return finish(event.key !== "Escape");
    setShown(true);
    const count = itemsNow.current?.length ?? 0;
    if (event.key === "Escape") finish(false);
    else if (event.key === "Enter") finish(true);
    else if (event.key === "ArrowLeft" || event.key === "ArrowUp") step(-1);
    else if (event.key === "ArrowRight" || event.key === "ArrowDown") step(1);
    else if (event.key === "Tab") step(event.shiftKey ? -1 : 1);
    else if (/^[1-5]$/.test(event.key) && Number(event.key) <= count) highlight(Number(event.key) - 1);
  };
  const controls = useRef<SwitcherControls>(null);
  controls.current = {
    step,
    keyDown,
    keyUp: (event) => releasesHold(event, hold) && finish(true),
    lostKeys: () => finish(false),
  };
  useEffect(() => {
    register({
      step: (by) => controls.current?.step(by),
      keyDown: (event) => controls.current?.keyDown(event),
      keyUp: (event) => controls.current?.keyUp(event),
      lostKeys: () => controls.current?.lostKeys(),
    });
    return () => register(null);
  }, [register]);

  // The list, asked again every quarter second while the keys are held; the
  // highlight stays on its tab while the tab is listed, and an empty list ends it.
  useEffect(() => {
    let current = true;
    const ask = async (first: boolean) => {
      const { items: listed } = await session.core.query(RecentTabs({ windowId: session.windowId }));
      if (!current || ended.current) return;
      const capped = listed.slice(0, 5);
      if (capped.length === 0) return finish(false);
      let next: number;
      if (first) {
        const opening = direction > 0 ? Math.min(1, capped.length - 1) : capped.length - 1;
        const steps = start.steps + earlySteps.current;
        next = (((opening + steps) % capped.length) + capped.length) % capped.length;
      } else {
        const highlighted = itemsNow.current?.[indexNow.current];
        const kept = highlighted ? capped.findIndex((item) => item.tabIds.includes(highlighted.focusedTabId)) : -1;
        next = kept >= 0 ? kept : Math.min(indexNow.current, capped.length - 1);
      }
      itemsNow.current = capped;
      indexNow.current = next;
      setItems(capped);
      setIndex(next);
      // What happened before the list came: the keyboard gone, or the keys let go.
      if (first && start.lost) finish(false);
      else if (first && (start.released || commitsWhenListed.current)) finish(true);
    };
    void ask(true);
    const timer = setInterval(() => void ask(false), 250);
    return () => {
      current = false;
      clearInterval(timer);
    };
    // The list is the window's; the direction is the opening press's.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session]);

  // The panel shows once the keys have been held a tenth of a second, and the
  // tab the window shows is pictured afresh for it.
  useEffect(() => {
    const timer = setTimeout(() => setShown(true), 100);
    return () => clearTimeout(timer);
  }, []);
  const shownItem = items?.[0];
  useEffect(() => {
    if (!shown || !shownItem) return;
    for (const tabId of shownItem.tabIds) {
      const pageId = pagesByTab.get(tabId);
      const page = pageId ? session.core.state.pages.get(pageId) : undefined;
      if (pageId && page?.live.url) pictures.capture(session.core, { pageId, tabId, address: page.live.url }, true);
    }
    // Once, as the panel shows.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shown, shownItem?.focusedTabId]);

  const pointer = useRef<{ x: number; y: number; moved: boolean } | null>(null);
  const pointed = (event: ReactPointerEvent, at: number) => {
    const resting = pointer.current;
    if (!resting) {
      pointer.current = { x: event.clientX, y: event.clientY, moved: false };
      return;
    }
    if (!resting.moved) resting.moved = Math.hypot(event.clientX - resting.x, event.clientY - resting.y) > 1;
    if (resting.moved && at !== indexNow.current) highlight(at);
  };

  const tabsById = new Map(spaces.flatMap((space) => space.tabs.map((tab) => [tab.id, tab] as const)));
  const spacesById = new Map(spaces.map((space) => [space.id, space]));
  const list = items ?? [];
  const mixesSpaces = new Set(list.map((item) => item.spaceId)).size > 1;
  const widths = list.map((item) => cardWidth(item.tabIds.length));
  const natural = {
    width: widths.reduce((sum, width) => sum + width, 0) + metrics.cardSpacing * Math.max(widths.length - 1, 0) + metrics.panelPadding * 2,
    height: metrics.thumbnailHeight + metrics.titleRowHeight + metrics.small * 3 + metrics.panelPadding * 2,
  };
  const scale = Math.min(1, (window.innerWidth - metrics.windowMargin * 2) / Math.max(natural.width, 1));
  const highlightX = widths.slice(0, index).reduce((sum, width) => sum + width + metrics.cardSpacing, 0);
  const spoken = (at: number) => {
    const item = list[at];
    if (!item) return "";
    const title = item.tabIds.map((tabId) => tabsById.get(tabId)?.displayTitle ?? "").join(", ");
    const space = mixesSpaces ? spacesById.get(item.spaceId)?.settings.name : undefined;
    return `${title}${space ? `, ${space}` : ""}, ${at + 1} of ${list.length}`;
  };

  return (
    <div className="recent-tabs-layer" onPointerMove={(event) => {
      // The pointer moving with the keys let go is a release the switcher missed.
      if (releasedUnheard(event)) finish(true);
    }}>
      {shown && items && (
        <>
          {/* A click outside the panel leaves things as they were, and goes no further. */}
          <div className="recent-tabs-backdrop" onPointerDown={(event) => {
            event.preventDefault();
            finish(false);
          }} />
          <div className="recent-tabs-panel" role="group" aria-label="Recent tabs"
            style={{ width: natural.width * scale, height: natural.height * scale }}
            onPointerDown={(event) => event.preventDefault()}>
            <div className="recent-tabs-cards" style={{ transform: scale < 1 ? `scale(${scale})` : undefined }}>
              {widths.length > 0 && (
                <motion.div className="recent-tabs-highlight" aria-hidden initial={false}
                  animate={{ x: highlightX, width: widths[index] ?? 0 }}
                  transition={matchMedia("(prefers-reduced-motion: reduce)").matches ? { duration: 0 } : tokens.surface} />
              )}
              {list.map((item, at) => (
                <button key={`${item.spaceId}-${item.tabIds.join()}`} className="recent-tabs-card" tabIndex={-1}
                  aria-label={spoken(at)} aria-current={at === index || undefined}
                  onPointerMove={(event) => pointed(event, at)}
                  onClick={() => {
                    indexNow.current = at;
                    finish(true);
                  }}>
                  {item.tabIds.map((tabId, page) => {
                    const tab = tabsById.get(tabId);
                    const space = spacesById.get(item.spaceId);
                    return tab ? (
                      <SwitcherPage key={tabId} session={session} tab={tab} pageId={pagesByTab.get(tabId) ?? null}
                        picture={pictures.picture(tabId)} width={pageWidth(item.tabIds.length)}
                        badge={mixesSpaces && page === item.tabIds.length - 1 ? space ?? null : null} />
                    ) : null;
                  })}
                </button>
              ))}
            </div>
          </div>
        </>
      )}
      <div className="visually-hidden" aria-live="polite">{shown ? spoken(index) : ""}</div>
    </div>
  );
}

/** RecentTabSwitcherMetrics. */
const metrics = Object.freeze({
  small: 8,
  cardSpacing: 8,
  panelPadding: 16,
  thumbnailHeight: 112,
  singlePageWidth: 176,
  splitPageWidth: 136,
  titleRowHeight: 24,
  windowMargin: 16,
});

function pageWidth(count: number): number {
  return count > 1 ? metrics.splitPageWidth : metrics.singlePageWidth;
}

function cardWidth(count: number): number {
  const pages = Math.max(count, 1);
  return pageWidth(count) * pages + metrics.small * (pages - 1) + metrics.small * 2;
}

/**
 * A page's picture over its icon and title, or its icon large on the tab's
 * colour while no picture exists, with its Space's icon in the picture's
 * corner when the list mixes Spaces.
 */
function SwitcherPage({ session, tab, pageId, picture, width, badge }: {
  session: Session;
  tab: TabState;
  pageId: string | null;
  picture: string | null;
  width: number;
  badge: SpaceState | null;
}) {
  const accent = tab.iconAccent;
  return (
    <div className="recent-tabs-page" style={{ width }}>
      <div className="recent-tabs-thumbnail"
        style={!picture && accent ? { background: `rgb(${accent.red * 255} ${accent.green * 255} ${accent.blue * 255} / 0.6)` } : undefined}>
        {picture ? <img src={picture} alt="" /> : <TabIcon session={session} tab={tab} pageId={pageId} size={40} />}
        {badge && (
          <span className="recent-tabs-badge">
            <SpaceIdentityIcon symbol={badge.settings.symbol} branding={badge.settings.look} size={20} />
          </span>
        )}
      </div>
      <div className="recent-tabs-title">
        <TabIcon session={session} tab={tab} pageId={pageId} size={16} />
        <span>{tab.displayTitle}</span>
      </div>
    </div>
  );
}
