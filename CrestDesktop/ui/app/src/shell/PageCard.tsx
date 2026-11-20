import { motion as tokens } from "@crest/design";
import { motion, type Transition } from "motion/react";
import { type ReactNode, type RefObject, useCallback, useContext, useEffect, useLayoutEffect, useRef, useState } from "react";

import type { Session } from "../boot";
import { type PageStill, pageStills } from "../spaces/page-stills";
import { StripPlace } from "../spaces/SpaceContentStrip";
import { useSpacePager } from "../spaces/space-pager";
import { useEngineVersion } from "../use-core";
import { useCardsSnap } from "./cards-snap";
import { usePointerHeld } from "./pointer-hold";

/**
 * The page card, clipped to Crest's corners. Inside Crest's Chromium it holds
 * the page's own surface, embedded into this document, so the card clips,
 * layers over and animates the page as SwiftUI does the Mac's page view. In
 * an ordinary browser frames stand in, and every live page keeps its frame so
 * moving between tabs keeps each page's state. What the page asks of the
 * person (`children`) layers over it.
 */
export function PageCard({ session, pageId, startPage, passive = false, focused = true, transition, children }: {
  session: Session;
  /** The page the card shows, or null where the tab shows none. */
  pageId: string | null;
  /** The Start Page the card shows in place of a page, or null. */
  startPage: ReactNode | null;
  /** Whether the card is another Space's, drawn still while the Space pager passes it. */
  passive?: boolean;
  /** Whether the card is the one of a split the window's chrome speaks for, which takes the keyboard. */
  focused?: boolean;
  /** How the card moves into a new place: the row's choice, or the window chrome's. */
  transition?: Transition;
  children?: ReactNode;
}) {
  // While a drag holds the pointer, the page is covered so the drag keeps its
  // events, and the card follows the sidebar's width at once, as the Mac's
  // resize does without animation.
  const held = usePointerHeld();
  // The sidebar taking its seat or leaving it changes the card's size each
  // frame, without a layout animation: even one of no length draws a frame
  // of the card scaled from its old box.
  const snaps = useCardsSnap();
  // A card the Space pager moves keeps its place in the layout: the strip moves it.
  const pager = useSpacePager();
  const moving = pager.phase !== "idle";
  // On a Start Page, and while the tab has no page, the card lets the Space's
  // backdrop through, keeping its edge and shadow, as the Mac's does.
  const clear = startPage !== null || !pageId;
  const card = useRef<HTMLElement>(null);
  // A slide brings the card on screen; at rest, and through a swipe that may
  // take it away, the window shows its page.
  const place = useContext(StripPlace);
  const arriving = moving && place !== null && place !== pager.originId;
  const shown = !passive && (!moving || place === pager.originId);
  const { still, cover, coverGone } = usePageStill(session, session.shell && !clear ? pageId : null, card, arriving, shown);
  return (
    <motion.main className={`page-card${clear ? " clear" : ""}${passive ? " passive" : ""}${still ? " still" : ""}`}
      layout={!passive && !moving && !snaps}
      transition={held ? { duration: 0 } : transition ?? tokens.chrome}
      // While it moves to a new place, as a split's columns resize, the card
      // gets a compositor layer of its own: moved from script each frame, it
      // would otherwise paint again, its shadow and all, every frame.
      onLayoutAnimationStart={() => card.current?.style.setProperty("will-change", "transform")}
      onLayoutAnimationComplete={() => card.current?.style.removeProperty("will-change")}
      ref={card}>
      {session.shell
        ? <EmbeddedPage session={session} pageId={pageId} passive={passive || !focused} asleep={!!still} />
        : !passive && <FramedPages session={session} pageId={pageId} all={focused} />}
      {still && <StillImage still={still} />}
      {cover && <StillImage still={cover.still} going={cover.going} onGone={coverGone} />}
      {startPage}
      {children}
      {held && <div className="page-cover" />}
    </motion.main>
  );
}

/**
 * The still a card shows while a slide brings it on screen, over its page
 * left asleep, and the still that covers the page once the strip has landed
 * until the page, woken, has drawn. A card the window shows at rest is
 * followed, so its page is pictured as the window is about to leave.
 */
function usePageStill(session: Session, pageId: string | null, card: RefObject<HTMLElement | null>, arriving: boolean,
  shown: boolean) {
  useEffect(() => {
    const element = card.current;
    if (!shown || !pageId || !element) return;
    return pageStills.showing(element, pageId);
  }, [pageId, card, shown]);
  // A still fits a card of its size; one taken at another size, before the
  // window or the sidebar changed, leaves the card to show its page.
  const candidate = arriving && pageId ? pageStills.still(pageId) : null;
  const [unfit, setUnfit] = useState<string | null>(null);
  const still = candidate && unfit !== candidate.url ? candidate : null;
  useLayoutEffect(() => {
    const box = card.current?.getBoundingClientRect();
    if (!candidate || !box) return;
    if (Math.abs(box.width - candidate.width) > 1.5 || Math.abs(box.height - candidate.height) > 1.5) setUnfit(candidate.url);
  }, [candidate, card]);
  // The still stays over the page as the card lands, until the page has drawn.
  const [cover, setCover] = useState<{ readonly still: PageStill; readonly going: boolean } | null>(null);
  const shownStill = useRef<PageStill | null>(null);
  useLayoutEffect(() => {
    if (still) {
      shownStill.current = still;
      return;
    }
    const landed = shownStill.current;
    shownStill.current = null;
    if (landed && !arriving) setCover({ still: landed, going: false });
  }, [still, arriving]);
  useEffect(() => {
    if (!cover || cover.going || !pageId) return;
    let current = true;
    void pageStills.drawn(session.core, pageId).then(() => {
      if (current) setCover((shown) => (shown && !shown.going ? { ...shown, going: true } : shown));
    });
    return () => {
      current = false;
    };
  }, [session, pageId, cover]);
  // A card that goes, or turns to another page, takes its cover with it.
  useEffect(() => setCover(null), [pageId]);
  const coverGone = useCallback(() => setCover(null), []);
  return { still, cover, coverGone };
}

/** A page's still, at its card's size in CSS pixels, so each of its pixels lands on one of the screen's. */
function StillImage({ still, going = false, onGone }: { still: PageStill; going?: boolean; onGone?: () => void }) {
  // A still that fades out goes once it has, or soon after should its fade not run.
  useEffect(() => {
    if (!going || !onGone) return;
    const timer = setTimeout(onGone, 400);
    return () => clearTimeout(timer);
  }, [going, onGone]);
  return (
    <img className={`page-still${going ? " going" : ""}`} src={still.url} alt="" draggable={false}
      style={{ width: still.width, height: still.height }} onTransitionEnd={going ? onGone : undefined} />
  );
}

/**
 * Gives what the window shows the keyboard, as the Mac's page becomes first
 * responder once the palette goes: the page, which has the keyboard exactly
 * while its embed is the interface's focused element, or the Start Page's
 * palette.
 */
export function focusShownPage() {
  const card = ".space-content-page.live .page-column.focused .page-card:not(.passive)";
  const shown = document.querySelector<HTMLElement>(`${card} .page-frame:not([data-hidden])`)
    ?? document.querySelector<HTMLElement>(`${card} .start-page .palette-input input`);
  shown?.focus();
}

/**
 * The surface each page embeds as, which stays the page's own for as long as
 * it lives: a card the Space pager brings in embeds a page it has shown
 * before at once, laying it out in place before it slides.
 */
const contentIds = new Map<string, string>();

/** The surface `pageId` embeds as, asked of the shell once and remembered, or null when it has none. */
export async function pageContentId(session: Session, pageId: string): Promise<string | null> {
  const known = contentIds.get(pageId);
  if (known) return known;
  const content = await session.shell?.embed(pageId);
  if (content) contentIds.set(pageId, content);
  return content ?? null;
}

/**
 * Marks the pages embedded under `root` as resized frame after frame, or no
 * longer. While marked, the window draws each of a page's sizes without
 * waiting for the page to lay out at it (`desktop-host.patch`), so a page
 * too heavy for a frame lags its card's edge instead of holding the motion,
 * showing what it last drew, clipped by the card or beside its background.
 */
export function setLiveResize(root: HTMLElement, live: boolean) {
  for (const embed of root.querySelectorAll("embed.page-frame")) embed.toggleAttribute("data-live-resize", live);
}

/**
 * A page embedded in its card. Asleep beneath its still while a slide brings
 * the card on screen, the embed stands unseen, which the engine takes as the
 * page hidden, so the page neither draws nor gives up its place: it wakes in
 * the same embedding as the strip lands, and its drawing from then on is that
 * embedding's, which the engine pictures it from.
 */
function EmbeddedPage({ session, pageId, passive, asleep = false }: {
  session: Session;
  pageId: string | null;
  passive: boolean;
  asleep?: boolean;
}) {
  const live = pageId ? session.core.state.pages.get(pageId)?.phase.name === "live" : false;
  const known = pageId && live ? contentIds.get(pageId) : undefined;
  const [embedded, setEmbedded] = useState<{ page: string; content: string } | null>(
    known && pageId ? { page: pageId, content: known } : null);
  useEffect(() => {
    if (!pageId || !live || embedded?.page === pageId) return;
    const cached = contentIds.get(pageId);
    if (cached) {
      setEmbedded({ page: pageId, content: cached });
      return;
    }
    let current = true;
    void pageContentId(session, pageId).then((content) => {
      if (content && current) setEmbedded({ page: pageId, content });
    });
    return () => {
      current = false;
    };
  }, [session, pageId, live, embedded]);
  // A page the window comes to show takes the keyboard, unless one of the
  // interface's own fields holds it; so does a split's card as it becomes
  // the focused one, from the page that had it.
  const shown = embedded && embedded.page === pageId && !passive ? embedded.page : null;
  const element = useRef<HTMLEmbedElement>(null);
  useEffect(() => {
    if (!shown) return;
    const active = document.activeElement;
    if (!active || active === document.body) focusShownPage();
    else if (active instanceof HTMLEmbedElement && active !== element.current) element.current?.focus();
  }, [shown]);
  if (!embedded || embedded.page !== pageId) return null;
  return (
    <embed
      ref={element}
      key={embedded.page}
      className="page-frame"
      type="application/x-chromium-surface-embed"
      data-content-id={embedded.content}
      tabIndex={-1}
      style={asleep ? { visibility: "hidden" } : undefined}
    />
  );
}

/**
 * A development browser's stand-in for embedded pages: frames, which the
 * focused card keeps for every live page so moving between tabs keeps each
 * page's state, and a split's other cards for their own page alone.
 */
function FramedPages({ session, pageId, all }: { session: Session; pageId: string | null; all: boolean }) {
  useEngineVersion(session);
  const pages = [...(session.engine?.pages.values() ?? [])].filter((page) => all || page.id === pageId);
  return (
    <>
      {pages.map((page) =>
        page.url ? (
          <iframe
            key={page.id}
            className="page-frame"
            src={page.url}
            title={page.url}
            data-hidden={page.id === pageId ? undefined : ""}
            style={{ visibility: page.id === pageId ? "visible" : "hidden" }}
          />
        ) : null,
      )}
    </>
  );
}
