<script lang="ts" module>
  import { motion as tokens, type Spring } from "@crest/design";

  /**
   * Where the sidebar is, as the Mac's BrowserSidebarPresentation: docked beside
   * the page, floating over it as a card, or collapsed off the window's edge
   * while the page fills the window.
   */
  export type SidebarPresentation = "docked" | "floating" | "collapsed";

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
  function leftThroughLeadingEdge(from: Point | null, to: Point, right: boolean): boolean {
    const x = (point: Point) => right ? innerWidth - point.x : point.x;
    if (x(to) >= 0) return false;
    const start = from ?? to;
    const crossing = x(start) === x(to) ? to.y : start.y - x(start) / (x(to) - x(start)) * (to.y - start.y);
    return crossing >= -edgeSlack && crossing <= innerHeight + edgeSlack;
  }

  /** A floating card's distance from the window's edges, as the Mac's floatingCardInset. */
  const cardInset = 7;

  /** Moves the sidebar between its places, as the Mac's BrowserRootModel morphs it. */
  export interface SidebarMorph {
    /** The sidebar's toggle, as Ctrl+S and its own button: hides a docked sidebar, and docks a floating or collapsed one. */
    toggle(): void;
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
</script>

<script lang="ts">
  import type { SpaceState } from "@crest/contracts";
  import type { ShellTransport } from "@crest/core-client";
  import { springCurve } from "@crest/design";
  import { flushSync, type Snippet, untrack } from "svelte";
  import { MediaQuery } from "svelte/reactivity";

  import { portal } from "../attachments";
  import { isMenuOpen } from "../menus";
  import { reducesMotion } from "../motion";
  import { sidebarOnRight, fullscreenSidebarReveal, sidebarMotionFactor, sidebarRevealDelay, sidebarRevealWidth, sidebarSlide } from "../appearance.svelte";
  import { tabPreview } from "./preview-state.svelte";
  import { useShellFrame } from "./WindowControls.svelte";
  import { holdCards } from "./cards-snap";
  import { holdLiveResize } from "./PageCard.svelte";
  import SidebarResizeHandle from "./SidebarResizeHandle.svelte";
  import { SpaceBanner } from "./SpaceBanner";

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
  let { presentation, onPresentation, morph, width, onResize, onResizeEnded, spaceId, spaces, shell, edgeHost, children }: {
    presentation: SidebarPresentation;
    onPresentation: (presentation: SidebarPresentation) => void;
    /** Where the window reaches the sidebar's toggle. */
    morph: { current: SidebarMorph | null };
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
    children?: Snippet;
  } = $props();

  let slot: HTMLDivElement | null = null;
  let margin = $state<HTMLDivElement | null>(null);
  let grip = $state<HTMLDivElement | null>(null);
  let shadow: HTMLDivElement | null = null;
  let strip = $state<HTMLDivElement | null>(null);
  let inset = $state<HTMLDivElement | null>(null);
  let reveal: ReturnType<typeof setTimeout> | undefined;
  let letGo: ReturnType<typeof setTimeout> | undefined;
  // Where the window last saw the pointer, and whether it has since left the
  // window through its leading edge, which keeps a card out until it's back.
  let pointer: Point | null = null;
  let outside = false;
  let returned = 0;
  // Until when a card the pointer brought out stays regardless.
  let revealing = 0;
  // Where the pointer rested as the strip appeared, until it moves.
  let resting: Point | null = null;
  let running: Morph | null = null;
  let cardsHeld: (() => void) | null = null;
  let liveResize: (() => void) | null = null;
  $effect(() => () => {
    clearTimeout(reveal);
    clearTimeout(letGo);
    if (running) cancelAnimationFrame(running.frame);
    cardsHeld?.();
    liveResize?.();
  });

  const isActive = () => (shell ? shell.frame.active : document.hasFocus());
  // A menu or one of the card's own fields in use holds it out.
  const held = () => {
    const active = document.activeElement;
    return tabPreview.shown !== null || isMenuOpen() || (active instanceof HTMLInputElement && !!slot?.contains(active));
  };
  // The pointer on the card's region: the card, its leading inset, its edge, and the margin beside it.
  const onCard = () => [slot, margin, grip, inset].some((part) => part?.matches(":hover"));
  const keepsCard = () => held() || onCard() || outside;

  // The card goes once the pointer has left it, unless something holds it: a
  // menu or one of its fields in use, a morph under way, the slide that
  // brought it out, or the pointer just back from beyond the leading edge,
  // which lets it go after the hold's delay.
  const retreat = () => {
    if (held() || running || presentation !== "floating") return;
    const wait = Math.max(revealing, returned + holdReleaseDelay) - performance.now();
    if (wait > 0) {
      if (letGo === undefined) {
        letGo = setTimeout(() => {
          letGo = undefined;
          if (!keepsCard() && !running && presentation === "floating") onPresentation("collapsed");
        }, wait);
      }
      return;
    }
    onPresentation("collapsed");
  };
  $effect(() => {
    if (!tabPreview.shown) untrack(() => { if (!keepsCard()) retreat(); });
  });
  // Out over the page as the pointer reached for it, held until it's all the way out.
  const browserFullscreen = new MediaQuery("(display-mode: fullscreen)");
  const hoverAllowed = $derived(fullscreenSidebarReveal.current || !(shell ? useShellFrame(shell).fullscreen : browserFullscreen.current));
  const revealByPointer = () => {
    clearTimeout(reveal);
    reveal = undefined;
    if (!hoverAllowed || presentation !== "collapsed" || running) return;
    revealing = performance.now() + revealHold * sidebarMotionFactor();
    onPresentation("floating");
  };
  // A pointer moving onto the strip, or along it, brings the card out once it
  // has stayed there the moment the Mac waits; one resting where the strip
  // appeared waits until it moves.
  const reach = (event: MouseEvent) => {
    const at = { x: event.clientX, y: event.clientY };
    if (resting) {
      if (resting.x === at.x && resting.y === at.y) return;
      resting = null;
    }
    if (!hoverAllowed || reveal !== undefined || !isActive()) return;
    reveal = setTimeout(() => {
      reveal = undefined;
      if (strip?.matches(":hover") || outside) revealByPointer();
    }, sidebarRevealDelay.current);
  };

  // The window follows the pointer for the edge: where it last was inside,
  // and where it went as it left. Out through the leading edge, a hidden
  // sidebar comes out at once and a card stays for as long as the pointer is
  // out; through any other edge, the card goes. An inactive window keeps no
  // card out.
  $effect(() => {
    const transport = shell;
    return untrack(() => {
      const moved = (event: MouseEvent) => {
        pointer = { x: event.clientX, y: event.clientY };
        if (!outside) return;
        outside = false;
        returned = performance.now();
      };
      const leftWindow = (event: MouseEvent) => {
        const through = leftThroughLeadingEdge(pointer, { x: event.clientX, y: event.clientY }, sidebarOnRight.current);
        pointer = null;
        if (through && isActive()) {
          outside = true;
          clearTimeout(letGo);
          letGo = undefined;
          if (presentation === "collapsed") revealByPointer();
          return;
        }
        clearTimeout(reveal);
        reveal = undefined;
        retreat();
      };
      const root = document.documentElement;
      document.addEventListener("mousemove", moved, true);
      root.addEventListener("mouseleave", leftWindow);
      const stopFrame = transport?.subscribeFrame(() => {
        if (transport.frame.active) return;
        outside = false;
        retreat();
      });
      return () => {
        document.removeEventListener("mousemove", moved, true);
        root.removeEventListener("mouseleave", leftWindow);
        stopFrame?.();
      };
    });
  });
  // The strip appears under a pointer resting at the edge, as the sidebar it
  // put away slides off, and the pointer hasn't reached for it again.
  $effect(() => {
    const now = presentation;
    untrack(() => {
      if (now === "collapsed") resting = pointer;
      if (now !== "floating") {
        clearTimeout(letGo);
        letGo = undefined;
      }
    });
  });

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
  let morphing = $state<MorphKind | null>(null);
  let dressing = $state<"in" | "out" | null>(null);
  let morphRevision = 0;
  const content = () => slot?.parentElement?.querySelector<HTMLElement>(":scope > .space-content") ?? null;
  const direction = () => sidebarOnRight.current ? -1 : 1;
  const leading = (rect: DOMRect) => sidebarOnRight.current ? innerWidth - rect.right : rect.left;
  const trailing = (rect: DOMRect) => leading(rect) + rect.width;
  const setOffsets = (offsets: Offsets | null, shadowBase = { x: 0, y: 0 }) => {
    const page = content();
    if (slot) slot.style.transform = offsets ? `translate(${direction() * offsets.x}px, ${offsets.y}px)` : "";
    if (shadow) {
      shadow.style.transform = offsets ? `translate(${shadowBase.x + direction() * offsets.x}px, ${shadowBase.y + offsets.y}px)` : "";
    }
    if (page) {
      const margin = offsets ? `calc(${offsets.page}px - var(--window-inset))` : "";
      page.style.marginLeft = sidebarOnRight.current ? "" : margin;
      page.style.marginRight = sidebarOnRight.current ? margin : "";
    }
  };
  // Script moves them each frame, so their own transitions stand aside
  // meanwhile, and until the frame after the morph hands them over. The pages
  // resize each frame too, so they follow without the window waiting on them,
  // the last size among them: a heavy page catches up once the motion rests.
  const holdTransitions = (holds: boolean) => {
    for (const element of [slot, shadow]) {
      if (!element) continue;
      element.style.transition = holds ? "none" : "";
      element.style.willChange = holds ? "transform" : "";
    }
    if (holds) liveResize ??= holdLiveResize();
    else {
      liveResize?.();
      liveResize = null;
    }
  };
  const stop = () => {
    const current = running;
    if (current) cancelAnimationFrame(current.frame);
    running = null;
    morphRevision++;
  };
  const releaseCards = () => {
    cardsHeld?.();
    cardsHeld = null;
  };
  const place = (next: SidebarPresentation) => {
    stop();
    setOffsets(null);
    holdTransitions(false);
    releaseCards();
    const release = holdCards();
    flushSync(() => {
      morphing = null;
      onPresentation(next);
    });
    release();
  };
  // The morph hands the sidebar and the page to the presentation it ends in,
  // which lays them out where its last frame drew them.
  const finish = (revision: number, final: SidebarPresentation) => {
    running = null;
    flushSync(() => {
      morphing = null;
      onPresentation(final);
    });
    setOffsets(null);
    releaseCards();
    requestAnimationFrame(() => {
      if (morphRevision !== revision) return;
      holdTransitions(false);
      // A card put away while the pointer was on it goes once the pointer has
      // left, sliding away now that its transitions are back.
      if (presentation === "floating" && !keepsCard()) onPresentation("collapsed");
    });
  };
  // The initial pose presents before the spring starts. Layout work setting up
  // the drawer must not advance its clock or skip its first frames.
  const begin = ({ kind, during, final, spring, dress, page: pageEnd, then }: MorphStep, began?: number) => {
    const element = slot;
    const page = content();
    const rows = element?.querySelector(".sidebar");
    if (!element || !page || !rows) {
      place(final);
      return;
    }
    // Where the sidebar and the page stand now: at rest, partway through a
    // slide of their own, or partway through another morph.
    const fromRows = rows.getBoundingClientRect();
    const fromPage = leading(page.getBoundingClientRect());
    stop();
    const revision = morphRevision;
    holdTransitions(true);
    setOffsets(null);
    element.style.transform = "none";
    if (shadow) shadow.style.transform = "none";
    flushSync(() => {
      cardsHeld ??= holdCards();
      morphing = kind;
      if (dress) dressing = dress;
      onPresentation(during);
    });
    // Where the presentation the morph runs in lays them out.
    const natural = rows.getBoundingClientRect();
    const naturalPage = leading(page.getBoundingClientRect());
    const slotBox = element.getBoundingClientRect();
    const shadowBox = shadow?.getBoundingClientRect();
    const shadowBase = shadowBox ? { x: slotBox.left - shadowBox.left, y: slotBox.top - shadowBox.top } : { x: 0, y: 0 };
    const from: Offsets = { x: leading(fromRows) - leading(natural), y: fromRows.top - natural.top, page: fromPage - naturalPage };
    // The page's edge at the window's full width, and beside the docked
    // sidebar: the sidebar's gap past its edge, where a full-width page
    // keeps the window's inset.
    const frame = getComputedStyle(element.parentElement ?? element);
    const gap = parseFloat(frame.getPropertyValue("--sidebar-gap")) || 0;
    const windowInset = parseFloat(frame.getPropertyValue("--window-inset")) || 0;
    const reaches = natural.width + gap - windowInset;
    const pageWide = during === "docked" ? -reaches : 0;
    const pageBeside = during === "docked" ? 0 : reaches;
    // A drawer going away hands the page the window's inset at once, as the
    // Mac's does when its sidebar leaves the column: the page steps out by
    // the difference and keeps that much more room beside the sidebar on
    // the way. One coming in keeps the docked gap throughout.
    const lead = kind === "drawer" && final === "collapsed" ? windowInset - gap : 0;
    // A drawer goes until the sidebar is past the window's edge, or comes
    // into its seat; a card settles where its presentation lays it out.
    const to: Offsets = kind === "drawer" && final === "collapsed"
      ? { x: -trailing(natural), y: 0, page: pageWide }
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
    const duration = spring.visualDuration * sidebarMotionFactor();
    if (duration === 0) {
      place(final);
      return;
    }
    const curve = springCurve({ ...spring, visualDuration: duration }, 0.001);
    const morph: Morph = { kind, final, frame: 0 };
    running = morph;
    // A step with one after it hands over once it has visibly arrived.
    const handOff = then ? duration * 1000 : Infinity;
    const step = (now: number) => {
      if (morphRevision !== revision) return;
      began ??= now;
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
    if (reducesMotion() || sidebarSlide.current === 0) {
      place(keepsCard() ? "floating" : "collapsed");
      return;
    }
    if (keepsCard()) begin({ kind: "card", during: "floating", final: "floating", spring: tokens.sidebarDrawer, dress: "in" });
    else begin({ kind: "drawer", during: "docked", final: "collapsed", spring: tokens.sidebarDrawer });
  };
  const dock = () => {
    if (reducesMotion() || sidebarSlide.current === 0) {
      place("docked");
      return;
    }
    // A sidebar put away comes out as the drawer. A card out over the page,
    // or on its way out or back, takes its seat as the Mac's does: the page
    // moves aside beneath the card as it comes to its floating place, then
    // the card settles into its seat, its dressing going as it does.
    const rows = slot?.querySelector(".sidebar")?.getBoundingClientRect();
    const away = running ? running.kind === "drawer" : presentation === "collapsed" && (!rows || trailing(rows) <= 0);
    if (away) begin({ kind: "drawer", during: "docked", final: "docked", spring: tokens.sidebarDrawer });
    else {
      begin({
        kind: "card", during: "floating", final: "docked", spring: tokens.sidebarDockApproach, page: "beside",
        then: { kind: "card", during: "docked", final: "docked", spring: tokens.sidebarDockAttachment, dress: "out" },
      });
    }
  };
  const target = () => running?.final ?? presentation;
  $effect(() => {
    const handle = morph;
    handle.current = { toggle: () => (target() === "docked" ? hide() : dock()) };
    return () => {
      handle.current = null;
    };
  });

  $effect(() => {
    const shown = dressing;
    if (!shown) return;
    const length = (shown === "in" ? tokens.sidebarDrawer : tokens.sidebarDockAttachment).visualDuration * 1000 * sidebarMotionFactor();
    const timer = setTimeout(() => {
      dressing = null;
    }, length + 50);
    return () => clearTimeout(timer);
  });
  const dressingClass = $derived(dressing ? ` dressing-${dressing}` : "");
  const left = (event: MouseEvent) => {
    // Out of the window, where it went decides.
    if (presentation !== "floating" || event.relatedTarget === null) return;
    setTimeout(() => {
      // The card's resize handle, riding its edge, counts as the card.
      if (!onCard()) retreat();
    }, 0);
  };
</script>

{#if presentation !== "collapsed" && !morphing}
  <!-- Docked, the handle stands in the gap between the sidebar and the
       page; floating, on the card's edge, above the card's hits. -->
  <SidebarResizeHandle
    bind:grip
    {width}
    center={presentation === "docked" ? `calc(${width}px + var(--sidebar-gap) / 2)` : `${cardInset + width}px`}
    floating={presentation === "floating"}
    {onResize}
    {onResizeEnded}
    onLeave={left}
  />
{/if}
<!-- The strip along the leading edge, and beside a card the inset between
     it and the window's edge, which counts as the card, both in the edge's host. -->
{#if presentation === "collapsed" && !morphing}
  <!-- Out of the window, where it went decides. -->
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div
    bind:this={strip}
    class="sidebar-edge"
    style:width="{sidebarRevealWidth.current}px"
    {@attach portal(() => edgeHost)}
    onmouseenter={reach}
    onmousemove={reach}
    onmouseleave={(event) => {
      if (event.relatedTarget === null) return;
      clearTimeout(reveal);
      reveal = undefined;
    }}
    onclick={() => {
      clearTimeout(reveal);
      reveal = undefined;
      onPresentation("floating");
    }}
  ></div>
{:else if presentation === "floating"}
  <!-- The card's whole region takes the pointer: the window's drag area
       would otherwise lie over its padding and the page's margin beside
       it, and a pointer there would have left the window. -->
  <div class="sidebar-card-region" style:width="{cardInset + width + retreatMargin}px" aria-hidden="true"
    {@attach portal(() => edgeHost)}></div>
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div bind:this={inset} class="sidebar-edge inset" style:width="{cardInset}px" onmouseleave={left}
    {@attach portal(() => edgeHost)}></div>
{/if}
{#if presentation === "floating"}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div bind:this={margin} class="sidebar-retreat-margin" style:width="{retreatMargin}px" onmouseleave={left}></div>
  <!-- The page's own pointer events never reach the interface, so the
       page beyond the margin is covered while the card floats, and the
       pointer reaching it puts the card away and the cover with it. -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="sidebar-retreat-zone" style:--retreat-edge="calc(7px + var(--sidebar-width) + {retreatMargin}px)" onmousemove={retreat}></div>
{/if}
<!-- The card's shadow, backdrop and sheen stay drawn, unseen, while the
     sidebar is docked, so the card comes out on its first frame rather
     than after the frames drawing them would take. -->
<div bind:this={shadow} class={`sidebar-card-shadow ${presentation}${dressingClass}`} aria-hidden="true"></div>
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div bind:this={slot} class={`sidebar-slot ${presentation}${dressingClass}${morphing ? " morphing" : ""}`} onmouseleave={left}>
  <SpaceBanner {spaces} {spaceId} />
  <div class="sidebar-card-sheen"></div>
  {@render children?.()}
</div>
