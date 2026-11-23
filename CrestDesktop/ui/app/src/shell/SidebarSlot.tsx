import type { SpaceState } from "@crest/contracts";
import type { ShellTransport } from "@crest/core-client";
import { type Spring, springCurve, motion as tokens } from "@crest/design";
import { type ReactNode, type RefObject, useEffect, useImperativeHandle, useRef, useState } from "react";
import { createPortal, flushSync } from "react-dom";

import { isMenuOpen } from "../menus";
import { holdCards } from "./cards-snap";
import { holdLiveResize } from "./PageCard";
import { holdPointer } from "./pointer-hold";
import { clampedSidebarWidth, sidebarWidths } from "./sidebar-layout";
import { SpaceBanner } from "./SpaceBanner";

/**
 * Where the sidebar is, as the Mac's BrowserSidebarPresentation: docked beside
 * the page, floating over it as a card, or collapsed off the window's edge
 * while the page fills the window.
 */
export type SidebarPresentation = "docked" | "floating" | "collapsed";

/** How long the pointer rests on the window's edge before the sidebar comes out, as the Mac's default. */
const revealDelay = 200;
/** How far past the card toward the page the pointer may go before the card retreats. */
const retreatMargin = 30;
/**
 * How far above or below the window a pointer leaving it may cross the line
 * of its sidebar edge and still count as leaving through that edge, as the
 * Mac's edgeSlack.
 */
const edgeSlack = 24;
/**
 * How long the card stays once a hold on it ends, as the Mac's
 * holdReleaseDelay: a pointer back over the page from beyond the window's
 * edge lets it go after this.
 */
const holdReleaseDelay = 150;
/** How long a card the pointer brought out stays before the pointer can let it go: its slide at the Mac's default length. */
const revealHold = tokens.sidebarReveal.visualDuration * 1000;

/** A point in the window, in CSS pixels. */
interface Point { readonly x: number; readonly y: number }

/**
 * Whether a pointer that left the window went out through its leading edge:
 * the line from where it was last seen inside to where it is now meets that
 * edge beside the window, give or take the slack, as the Mac's
 * hasPointerLeftThroughStripEdge decides.
 */
function leftThroughLeadingEdge(from: Point | null, to: Point): boolean {
  if (to.x >= 0) return false;
  const start = from ?? to;
  const crossing = start.x === to.x ? to.y : start.y + ((0 - start.x) / (to.x - start.x)) * (to.y - start.y);
  return crossing >= -edgeSlack && crossing <= innerHeight + edgeSlack;
}

/** A floating card's distance from the window's edges, as the Mac's floatingCardInset. */
const cardInset = 7;

/** Moves the sidebar between its places, as the Mac's BrowserRootModel morphs it. */
export interface SidebarMorph {
  /** The sidebar's toggle, as Ctrl+S and its own button: hides a docked sidebar, and docks a floating or collapsed one. */
  toggle(): void;
}

function reducesMotion(): boolean {
  return matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/**
 * Where a morph has the sidebar and the page stand, from where the
 * presentation it runs in lays them out: the sidebar moved by `x` and `y`,
 * and the page's leading edge by `page`.
 */
interface Offsets {
  readonly x: number;
  readonly y: number;
  readonly page: number;
}

/**
 * How the sidebar moves between its places. A drawer slides the sidebar in
 * or out beside the page, whose edge stays beside the sidebar's; a card
 * stands over the page, which moves beneath it.
 */
type MorphKind = "drawer" | "card";

/** A step of a morph: how it moves, in which presentation, and what comes after it. */
interface MorphStep {
  readonly kind: MorphKind;
  /** The presentation that lays out the sidebar and the page while the step runs. */
  readonly during: SidebarPresentation;
  /** Where the sidebar is once the morph ends. */
  readonly final: SidebarPresentation;
  readonly spring: Spring;
  /** The card's dressing coming in or going as the step starts. */
  readonly dress?: "in" | "out";
  /** Where a card's step leaves the page: beside the docked sidebar, or across the window. */
  readonly page?: "beside" | "wide";
  /** The step that takes over once this one has visibly arrived, as the Mac's completion delays wait. */
  readonly then?: MorphStep;
}

/** A morph under way, drawn each frame from script. */
interface Morph {
  readonly kind: MorphKind;
  /** Where the sidebar is once it ends. */
  readonly final: SidebarPresentation;
  frame: number;
}

/** A length in whole device pixels, so what moves stays sharp on every frame. */
function devicePixels(length: number): number {
  return Math.round(length * devicePixelRatio) / devicePixelRatio;
}

/**
 * Holds the sidebar where its presentation puts it. While collapsed, a strip
 * along the window's leading edge brings it out as a floating card when the
 * pointer moves onto it and stays a moment, or clicks it, and a pointer that
 * leaves the window through that edge brings it out at once, as the Mac's
 * BrowserCollapsedSidebarHoverTrackingView does; only the active window's
 * comes out, and a pointer resting where the strip appears waits until it
 * moves. The card stays until it has come all the way out, and while the
 * pointer is out past the window's leading edge; it retreats once the
 * pointer leaves it and the margin beside it for the page, or leaves the
 * window through another edge, or the window stops being active, unless a
 * menu or one of its fields is in use (BrowserSidebarHoverTrackingView).
 * Docked or floating, its edge beside the page resizes it.
 */
export function SidebarSlot({ presentation, onPresentation, morph, width, onResize, onResizeEnded, spaceId, spaces, shell, edgeHost,
  children }: {
  presentation: SidebarPresentation;
  onPresentation: (presentation: SidebarPresentation) => void;
  /** Where the window reaches the sidebar's toggle. */
  morph: RefObject<SidebarMorph | null>;
  /** The sidebar's width, which the docked column and the floating card share. */
  width: number;
  onResize: (width: number) => void;
  /** A resize settled on `width`, to keep for the window. */
  onResizeEnded: (width: number) => void;
  spaceId: string;
  /** The window's Spaces, whose banners the card blends between as the Space pager moves. */
  spaces: readonly SpaceState[];
  /** The window's shell, which says whether the window is the active one; none in a development browser. */
  shell: ShellTransport | null;
  /**
   * Where the window's leading edge takes the pointer: a layer after the page
   * area, since Chromium lays each box's drag area over those before it, and
   * the page area's margin moves the window.
   */
  edgeHost: HTMLElement | null;
  children: ReactNode;
}) {
  const slot = useRef<HTMLDivElement>(null);
  const margin = useRef<HTMLDivElement>(null);
  const grip = useRef<HTMLDivElement>(null);
  const shadow = useRef<HTMLDivElement>(null);
  const strip = useRef<HTMLDivElement>(null);
  const inset = useRef<HTMLDivElement>(null);
  const reveal = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const letGo = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  // Where the window last saw the pointer, and whether it has since left the
  // window through its leading edge, which keeps a card out until it's back.
  const pointer = useRef<Point | null>(null);
  const outside = useRef(false);
  const returned = useRef(0);
  // Until when a card the pointer brought out stays regardless.
  const revealing = useRef(0);
  // Where the pointer rested as the strip appeared, until it moves.
  const resting = useRef<Point | null>(null);
  const running = useRef<Morph | null>(null);
  const cardsHeld = useRef<(() => void) | null>(null);
  const liveResize = useRef<(() => void) | null>(null);
  useEffect(() => () => {
    clearTimeout(reveal.current);
    clearTimeout(letGo.current);
    if (running.current) cancelAnimationFrame(running.current.frame);
    cardsHeld.current?.();
    liveResize.current?.();
  }, []);
  const shown = useRef(presentation);
  shown.current = presentation;

  const isActive = () => (shell ? shell.frame.active : document.hasFocus());
  // A menu or one of the card's own fields in use holds it out.
  const held = () => {
    const active = document.activeElement;
    return isMenuOpen() || (active instanceof HTMLInputElement && !!slot.current?.contains(active));
  };
  // The pointer on the card's region: the card, its leading inset, its edge, and the margin beside it.
  const onCard = () => [slot, margin, grip, inset].some((part) => part.current?.matches(":hover"));
  const keepsCard = () => held() || onCard() || outside.current;

  // The card goes once the pointer has left it, unless something holds it: a
  // menu or one of its fields in use, a morph under way, the slide that
  // brought it out, or the pointer just back from beyond the leading edge,
  // which lets it go after the hold's delay.
  const retreat = () => {
    if (held() || running.current || shown.current !== "floating") return;
    const wait = Math.max(revealing.current, returned.current + holdReleaseDelay) - performance.now();
    if (wait > 0) {
      if (letGo.current === undefined) {
        letGo.current = setTimeout(() => {
          letGo.current = undefined;
          if (!keepsCard() && !running.current && shown.current === "floating") onPresentation("collapsed");
        }, wait);
      }
      return;
    }
    onPresentation("collapsed");
  };
  // Out over the page as the pointer reached for it, held until it's all the way out.
  const revealByPointer = () => {
    clearTimeout(reveal.current);
    reveal.current = undefined;
    if (shown.current !== "collapsed" || running.current) return;
    revealing.current = performance.now() + revealHold;
    onPresentation("floating");
  };
  // A pointer moving onto the strip, or along it, brings the card out once it
  // has stayed there the moment the Mac waits; one resting where the strip
  // appeared waits until it moves.
  const reach = (event: React.MouseEvent) => {
    const at = { x: event.clientX, y: event.clientY };
    if (resting.current) {
      if (resting.current.x === at.x && resting.current.y === at.y) return;
      resting.current = null;
    }
    if (reveal.current !== undefined || !isActive()) return;
    reveal.current = setTimeout(() => {
      reveal.current = undefined;
      if (strip.current?.matches(":hover") || outside.current) revealByPointer();
    }, revealDelay);
  };

  // The window follows the pointer for the edge: where it last was inside,
  // and where it went as it left. Out through the leading edge, a hidden
  // sidebar comes out at once and a card stays for as long as the pointer is
  // out; through any other edge, the card goes. An inactive window keeps no
  // card out.
  useEffect(() => {
    const moved = (event: MouseEvent) => {
      pointer.current = { x: event.clientX, y: event.clientY };
      if (!outside.current) return;
      outside.current = false;
      returned.current = performance.now();
    };
    const leftWindow = (event: MouseEvent) => {
      const through = leftThroughLeadingEdge(pointer.current, { x: event.clientX, y: event.clientY });
      pointer.current = null;
      if (through && isActive()) {
        outside.current = true;
        clearTimeout(letGo.current);
        letGo.current = undefined;
        if (shown.current === "collapsed") revealByPointer();
        return;
      }
      clearTimeout(reveal.current);
      reveal.current = undefined;
      retreat();
    };
    const root = document.documentElement;
    document.addEventListener("mousemove", moved, true);
    root.addEventListener("mouseleave", leftWindow);
    const stopFrame = shell?.subscribeFrame(() => {
      if (shell.frame.active) return;
      outside.current = false;
      retreat();
    });
    return () => {
      document.removeEventListener("mousemove", moved, true);
      root.removeEventListener("mouseleave", leftWindow);
      stopFrame?.();
    };
    // The handlers read the slot's state through refs.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shell]);
  // The strip appears under a pointer resting at the edge, as the sidebar it
  // put away slides off, and the pointer hasn't reached for it again.
  useEffect(() => {
    if (presentation === "collapsed") resting.current = pointer.current;
    if (presentation !== "floating") {
      clearTimeout(letGo.current);
      letGo.current = undefined;
    }
  }, [presentation]);

  // Taking its seat and leaving it at the toggle, the sidebar moves as a
  // drawer, as the Mac's page moves with it: the page's edge stays beside
  // the sidebar's every frame, the page laid out at each width on the way.
  // Put away while the pointer is on it, it turns into the card where it
  // stands, the page growing beneath it, and stays until the pointer leaves;
  // a card out over the page takes its seat by moving the page aside beneath
  // it, settling into the column as it does. Each frame sets the sidebar's
  // place and the page's edge together, so the two never part, and the last
  // frame is where the presentation lays them out, so nothing moves as the
  // morph hands them over.
  const [morphing, setMorphing] = useState<MorphKind | null>(null);
  const [dressing, setDressing] = useState<"in" | "out" | null>(null);
  const morphRevision = useRef(0);
  const content = () => slot.current?.parentElement?.querySelector<HTMLElement>(":scope > .space-content") ?? null;
  const setOffsets = (offsets: Offsets | null, shadowBase = { x: 0, y: 0 }) => {
    const page = content();
    if (slot.current) slot.current.style.transform = offsets ? `translate(${offsets.x}px, ${offsets.y}px)` : "";
    if (shadow.current) {
      shadow.current.style.transform = offsets ? `translate(${shadowBase.x + offsets.x}px, ${shadowBase.y + offsets.y}px)` : "";
    }
    if (page) page.style.marginLeft = offsets ? `calc(${offsets.page}px - var(--window-inset))` : "";
  };
  // Script moves them each frame, so their own transitions stand aside
  // meanwhile, and until the frame after the morph hands them over. The pages
  // resize each frame too, so they follow without the window waiting on them,
  // the last size among them: a heavy page catches up once the motion rests.
  const holdTransitions = (held: boolean) => {
    for (const element of [slot.current, shadow.current]) {
      if (!element) continue;
      element.style.transition = held ? "none" : "";
      element.style.willChange = held ? "transform" : "";
    }
    if (held) liveResize.current ??= holdLiveResize();
    else {
      liveResize.current?.();
      liveResize.current = null;
    }
  };
  const stop = () => {
    const current = running.current;
    if (current) cancelAnimationFrame(current.frame);
    running.current = null;
    morphRevision.current++;
  };
  const releaseCards = () => {
    cardsHeld.current?.();
    cardsHeld.current = null;
  };
  const place = (next: SidebarPresentation) => {
    stop();
    setOffsets(null);
    holdTransitions(false);
    releaseCards();
    const release = holdCards();
    flushSync(() => {
      setMorphing(null);
      onPresentation(next);
    });
    release();
  };
  // The morph hands the sidebar and the page to the presentation it ends in,
  // which lays them out where its last frame drew them.
  const finish = (revision: number, final: SidebarPresentation) => {
    running.current = null;
    flushSync(() => {
      setMorphing(null);
      onPresentation(final);
    });
    setOffsets(null);
    releaseCards();
    requestAnimationFrame(() => {
      if (morphRevision.current !== revision) return;
      holdTransitions(false);
      // A card put away while the pointer was on it goes once the pointer has
      // left, sliding away now that its transitions are back.
      if (shown.current === "floating" && !keepsCard()) onPresentation("collapsed");
    });
  };
  // A step starts its clock as it begins, or where the step before it
  // handed over, so it moves on the very next frame.
  const begin = ({ kind, during, final, spring, dress, page: pageEnd, then }: MorphStep, began = performance.now()) => {
    const element = slot.current;
    const page = content();
    const rows = element?.querySelector(".sidebar");
    if (!element || !page || !rows) {
      place(final);
      return;
    }
    // Where the sidebar and the page stand now: at rest, partway through a
    // slide of their own, or partway through another morph.
    const fromRows = rows.getBoundingClientRect();
    const fromPage = page.getBoundingClientRect().left;
    stop();
    const revision = morphRevision.current;
    holdTransitions(true);
    setOffsets(null);
    element.style.transform = "none";
    if (shadow.current) shadow.current.style.transform = "none";
    flushSync(() => {
      cardsHeld.current ??= holdCards();
      setMorphing(kind);
      if (dress) setDressing(dress);
      onPresentation(during);
    });
    // Where the presentation the morph runs in lays them out.
    const natural = rows.getBoundingClientRect();
    const naturalPage = page.getBoundingClientRect().left;
    const slotBox = element.getBoundingClientRect();
    const shadowBox = shadow.current?.getBoundingClientRect();
    const shadowBase = shadowBox ? { x: slotBox.left - shadowBox.left, y: slotBox.top - shadowBox.top } : { x: 0, y: 0 };
    const from: Offsets = { x: fromRows.left - natural.left, y: fromRows.top - natural.top, page: fromPage - naturalPage };
    // The page's edge at the window's full width, and beside the docked
    // sidebar: the sidebar's gap past its edge, where a full-width page
    // keeps the window's inset.
    const frame = getComputedStyle(element.parentElement ?? element);
    const gap = parseFloat(frame.getPropertyValue("--sidebar-gap")) || 0;
    const inset = parseFloat(frame.getPropertyValue("--window-inset")) || 0;
    const reach = natural.width + gap - inset;
    const pageWide = during === "docked" ? -reach : 0;
    const pageBeside = during === "docked" ? 0 : reach;
    // A drawer going away hands the page the window's inset at once, as the
    // Mac's does when its sidebar leaves the column: the page steps out by
    // the difference and keeps that much more room beside the sidebar on
    // the way. One coming in keeps the docked gap throughout.
    const lead = kind === "drawer" && final === "collapsed" ? inset - gap : 0;
    // A drawer goes until the sidebar is past the window's edge, or comes
    // into its seat; a card settles where its presentation lays it out.
    const to: Offsets = kind === "drawer" && final === "collapsed"
      ? { x: -natural.right, y: 0, page: pageWide }
      : { x: 0, y: 0, page: (pageEnd ?? (final === "docked" ? "beside" : "wide")) === "beside" ? pageBeside : pageWide };
    // A drawer's page keeps its edge beside the sidebar's, within its own
    // reach; beneath a card, the page moves on the card's spring.
    const pageAt = (x: number, fraction: number) => kind === "drawer"
      ? Math.min(pageBeside + lead, Math.max(pageWide, x + lead))
      : from.page + (to.page - from.page) * fraction;
    const offsetsAt = (fraction: number): Offsets => {
      const x = devicePixels(from.x + (to.x - from.x) * fraction);
      return { x, y: devicePixels(from.y + (to.y - from.y) * fraction), page: devicePixels(pageAt(x, fraction)) };
    };
    setOffsets(offsetsAt(0), shadowBase);
    const curve = springCurve(spring, 0.001);
    const morph: Morph = { kind, final, frame: 0 };
    running.current = morph;
    // A step with one after it hands over once it has visibly arrived.
    const handOff = then ? spring.visualDuration * 1000 : Infinity;
    const step = (now: number) => {
      if (morphRevision.current !== revision) return;
      const elapsed = Math.max(0, now - began);
      if (then && elapsed >= handOff) {
        // This frame's place, from which the next step goes on.
        setOffsets(offsetsAt(curve.position(elapsed / 1000)), shadowBase);
        begin(then, now);
        return;
      }
      if (elapsed >= curve.duration) {
        finish(revision, final);
        return;
      }
      setOffsets(offsetsAt(curve.position(elapsed / 1000)), shadowBase);
      morph.frame = requestAnimationFrame(step);
    };
    morph.frame = requestAnimationFrame(step);
  };
  const hide = () => {
    if (reducesMotion()) {
      place(keepsCard() ? "floating" : "collapsed");
      return;
    }
    if (keepsCard()) begin({ kind: "card", during: "floating", final: "floating", spring: tokens.sidebarMorph, dress: "in" });
    else begin({ kind: "drawer", during: "docked", final: "collapsed", spring: tokens.sidebarMorph });
  };
  const dock = () => {
    if (reducesMotion()) {
      place("docked");
      return;
    }
    // A sidebar put away comes out as the drawer. A card out over the page,
    // or on its way out or back, takes its seat as the Mac's does: the page
    // moves aside beneath the card as it comes to its floating place, then
    // the card settles into its seat, its dressing going as it does.
    const rows = slot.current?.querySelector(".sidebar")?.getBoundingClientRect();
    const away = running.current ? running.current.kind === "drawer" : shown.current === "collapsed" && (!rows || rows.right <= 0);
    if (away) begin({ kind: "drawer", during: "docked", final: "docked", spring: tokens.sidebarMorph });
    else {
      begin({
        kind: "card", during: "floating", final: "docked", spring: tokens.sidebarDockApproach, page: "beside",
        then: { kind: "card", during: "docked", final: "docked", spring: tokens.sidebarDockAttachment, dress: "out" },
      });
    }
  };
  const target = () => running.current?.final ?? shown.current;
  useImperativeHandle(morph, () => ({ toggle: () => (target() === "docked" ? hide() : dock()) }));

  useEffect(() => {
    if (!dressing) return;
    const length = (dressing === "in" ? tokens.sidebarMorph : tokens.sidebarDockAttachment).visualDuration * 1000;
    const timer = setTimeout(() => setDressing(null), length + 50);
    return () => clearTimeout(timer);
  }, [dressing]);
  const dressingClass = dressing ? ` dressing-${dressing}` : "";
  const left = (event: React.MouseEvent) => {
    // Out of the window, where it went decides.
    if (presentation !== "floating" || event.relatedTarget === null) return;
    setTimeout(() => {
      // The card's resize handle, riding its edge, counts as the card.
      if (!onCard()) retreat();
    }, 0);
  };
  // The strip along the leading edge, and beside a card the inset between
  // it and the window's edge, which counts as the card.
  const edge = presentation === "collapsed" && !morphing ? (
    <div
      ref={strip}
      className="sidebar-edge"
      onMouseEnter={reach}
      onMouseMove={reach}
      // Out of the window, where it went decides.
      onMouseLeave={(event) => {
        if (event.relatedTarget === null) return;
        clearTimeout(reveal.current);
        reveal.current = undefined;
      }}
      onClick={() => {
        clearTimeout(reveal.current);
        reveal.current = undefined;
        onPresentation("floating");
      }}
    />
  ) : presentation === "floating" ? (
    <>
      {/* The card's whole region takes the pointer: the window's drag area
          would otherwise lie over its padding and the page's margin beside
          it, and a pointer there would have left the window. */}
      <div className="sidebar-card-region" style={{ width: cardInset + width + retreatMargin }} aria-hidden />
      <div ref={inset} className="sidebar-edge inset" style={{ width: cardInset }} onMouseLeave={left} />
    </>
  ) : null;

  return (
    <>
      {presentation !== "collapsed" && !morphing && (
        <SidebarResizeHandle
          grip={grip}
          width={width}
          // Docked, the handle stands in the gap between the sidebar and the
          // page; floating, on the card's edge, above the card's hits.
          center={presentation === "docked" ? `calc(${width}px + var(--sidebar-gap) / 2)` : `${cardInset + width}px`}
          floating={presentation === "floating"}
          onResize={onResize}
          onResizeEnded={onResizeEnded}
          onLeave={left}
        />
      )}
      {edge && (edgeHost ? createPortal(edge, edgeHost) : edge)}
      {presentation === "floating" && (
        <>
          <div ref={margin} className="sidebar-retreat-margin" style={{ width: retreatMargin }} onMouseLeave={left} />
          {/* The page's own pointer events never reach the interface, so the
              page beyond the margin is covered while the card floats, and the
              pointer reaching it puts the card away and the cover with it. */}
          <div className="sidebar-retreat-zone" style={{ left: `calc(7px + var(--sidebar-width) + ${retreatMargin}px)` }}
            onMouseMove={retreat} />
        </>
      )}
      {/* The card's shadow, backdrop and sheen stay drawn, unseen, while the
          sidebar is docked, so the card comes out on its first frame rather
          than after the frames drawing them would take. */}
      <div ref={shadow} className={`sidebar-card-shadow ${presentation}${dressingClass}`} aria-hidden />
      <div ref={slot} className={`sidebar-slot ${presentation}${dressingClass}${morphing ? " morphing" : ""}`} onMouseLeave={left}>
        <SpaceBanner spaces={spaces} spaceId={spaceId} />
        <div className="sidebar-card-sheen" />
        {children}
      </div>
    </>
  );
}

/** The handle's grip, its indicator, and how far an arrow key moves it, as the Mac's BrowserSidebarResizeHandleMetrics. */
const handleMetrics = { hitWidth: 16, step: 20 } as const;

/**
 * The sidebar's resize handle, as the Mac's BrowserSidebarResizeHandle: a
 * grip at the sidebar's edge that a drag widens or narrows within its
 * bounds, the page following live, showing a thin bar while it moves. The
 * resize settles when the drag ends however it ends, or when the handle goes
 * under it. Its arrow keys step the width, as the Mac's adjustable action does.
 */
function SidebarResizeHandle({ grip, width, center, floating, onResize, onResizeEnded, onLeave }: {
  grip: RefObject<HTMLDivElement | null>;
  width: number;
  /** Where the grip's middle stands, as a CSS length from the window's leading edge. */
  center: string;
  floating: boolean;
  onResize: (width: number) => void;
  onResizeEnded: (width: number) => void;
  onLeave: (event: React.MouseEvent) => void;
}) {
  const drag = useRef<{
    readonly pointerId: number;
    readonly x: number;
    readonly width: number;
    /** Lets go of the pointer and of the pages, which the drag resizes each move. */
    readonly release: () => void;
  } | null>(null);
  const latest = useRef(width);
  latest.current = width;
  const ended = useRef(onResizeEnded);
  ended.current = onResizeEnded;
  const [active, setActive] = useState(false);
  const finish = () => {
    const begun = drag.current;
    if (!begun) return;
    drag.current = null;
    begun.release();
    setActive(false);
    ended.current(latest.current);
  };
  // A handle that goes mid-drag, as when the sidebar is put away, still settles the width it reached.
  useEffect(() => () => {
    const begun = drag.current;
    if (!begun) return;
    begun.release();
    ended.current(latest.current);
  }, []);
  const resize = (next: number) => {
    latest.current = clampedSidebarWidth(next);
    onResize(latest.current);
  };

  return (
    <div
      ref={grip}
      className={`sidebar-resize-handle${active ? " active" : ""}${floating ? " floating" : ""}`}
      style={{ left: `calc(${center} - ${handleMetrics.hitWidth / 2}px)`, width: handleMetrics.hitWidth }}
      role="separator"
      aria-orientation="vertical"
      aria-label="Resize Sidebar"
      aria-valuenow={Math.round(width)}
      aria-valuemin={sidebarWidths.minimum}
      aria-valuemax={sidebarWidths.maximum}
      tabIndex={0}
      onPointerDown={(event) => {
        if (event.button !== 0 || drag.current) return;
        // The handle moves as the width changes, so the drag is measured from where it began.
        event.preventDefault();
        event.currentTarget.setPointerCapture(event.pointerId);
        const pointer = holdPointer();
        const pages = holdLiveResize();
        drag.current = {
          pointerId: event.pointerId, x: event.clientX, width,
          release: () => {
            pointer();
            pages();
          },
        };
        setActive(true);
      }}
      onPointerMove={(event) => {
        const begun = drag.current;
        if (begun && event.pointerId === begun.pointerId) resize(begun.width + event.clientX - begun.x);
      }}
      onPointerUp={finish}
      onPointerCancel={finish}
      onLostPointerCapture={finish}
      onKeyDown={(event) => {
        const step = event.key === "ArrowRight" ? handleMetrics.step : event.key === "ArrowLeft" ? -handleMetrics.step : 0;
        if (step === 0) return;
        event.preventDefault();
        resize(width + step);
        ended.current(latest.current);
      }}
      onMouseLeave={onLeave}
    >
      <span className="sidebar-resize-indicator" aria-hidden />
    </div>
  );
}
