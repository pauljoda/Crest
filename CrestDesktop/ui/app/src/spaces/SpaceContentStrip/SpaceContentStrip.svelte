<script lang="ts" module>
  import type { SpaceState } from "@crest/contracts";

  import { reducesMotion } from "../../motion";
  import {
    animateSettle, applyLeafStyle, type LeafStyle, type PagerFrame, placedIndex, spacePager, stopSettle,
  } from "../space-pager";

  /** Whether pages slide when the window changes Space, as the person and the system allow; otherwise they fade. */
  function slidesPages(): boolean {
    let animates = true;
    try {
      animates = localStorage.getItem("crest.appearance.animate-space-pages") !== "false";
    } catch {
      // The preference stays at its default.
    }
    return animates && !reducesMotion();
  }

  /** Where a card stands, or how opaque it is, at the pager's frame. */
  function cardStyle(id: string, frame: PagerFrame, strip: PageStrip, liveId: string, slides: boolean, leaving: string | null,
    warming: ReadonlyMap<string, HTMLElement>): LeafStyle {
    const resting = frame.originId ?? liveId;
    const restingIndex = strip.ids.indexOf(resting);
    const selected = strip.ids.indexOf(liveId);
    const index = strip.ids.indexOf(id);
    // A card in motion gets a compositor layer of its own; at rest it gives the layer up.
    const willChange = frame.phase === "idle" ? "" : slides ? "transform" : "opacity";
    if (warming.has(id) && !(frame.phase === "idle" && id === resting)) {
      // In place and unseen until its page has laid out there. Its own layer
      // for opacity has the compositor draw, and so rasterize, it even unseen.
      return { transform: "", visibility: "", opacity: "0", zIndex: "-1", willChange: "transform, opacity" };
    }
    // The card a dissolve leaves lies over the one it shows, fading away.
    if (id === leaving) return { transform: "", visibility: "", zIndex: "2", willChange };
    // A Space beside the shown one waits drawn, in place and unseen, on a layer
    // of its own, for a slide to take it up: the layer is rasterized once, at
    // rest, rather than in the slide's first frames.
    if (id !== resting && !frame.pages.includes(id) && frame.prepared.includes(id)) {
      return { transform: "", visibility: "", opacity: "0", zIndex: "-1", willChange: "transform, opacity" };
    }
    if (frame.phase === "idle" || index < 0) {
      // At rest only the Space the pager shows; one it hasn't taken up yet waits unseen.
      const shows = id === resting;
      return { transform: "", opacity: "", zIndex: shows ? "1" : "0", visibility: shows ? "" : "hidden", willChange };
    }
    // A Space that shares its place with the shown one leaves that place to it.
    if (strip.yieldsPlace(index, selected)) return { visibility: "hidden", willChange };
    if (slides) {
      // A card beyond the area stays visible to the engine: the area's clip
      // hides it, and a page that came hidden would not draw as it slides in.
      const offset = strip.offset(index, frame.position);
      return { visibility: "", transform: offset === 0 ? "" : `translateX(${offset * 100}%)`, opacity: "", zIndex: "", willChange };
    }
    const opacity = strip.opacity(index, frame.position, restingIndex);
    return {
      transform: "",
      visibility: opacity > 0 ? "" : "hidden",
      opacity: `${opacity}`,
      zIndex: `${Math.round(strip.stacking(index, frame.position, restingIndex) * 100)}`,
      willChange,
    };
  }

  /**
   * Places each card. A slide's settle runs on the compositor, as the cards
   * hold the window's pages and shadows, which repainting each frame costs more
   * than an integrated GPU has; a swipe, a fade and rest are written each frame.
   * A card still warming, or the one a dissolve leaves, keeps its own style.
   */
  function arrange(frame: PagerFrame, strip: PageStrip, pages: ReadonlyMap<string, HTMLDivElement>, liveId: string,
    slides: boolean, leaving: string | null, warming: ReadonlyMap<string, HTMLElement>) {
    const settle = slides && frame.phase === "settling" ? spacePager.settle : null;
    for (const [id, element] of pages) {
      if (settle && !warming.has(id) && id !== leaving) {
        animateSettle(element, settle, (at) => cardStyle(id, at, strip, liveId, slides, leaving, warming));
        continue;
      }
      stopSettle(element);
      applyLeafStyle(element, cardStyle(id, frame, strip, liveId, slides, leaving, warming));
    }
  }

  /**
   * The Mac's SpacePageStrip: the Spaces in the order the pager runs along,
   * and the places where a Space and the next show the same pinned tab of
   * their group, which count as one.
   */
  class PageStrip {
    readonly ids: readonly string[];
    readonly #shared: ReadonlySet<number>;

    constructor(order: readonly string[], spaces: readonly SpaceState[], shownPins: ReadonlyMap<string, string>) {
      this.ids = order;
      const byId = new Map(spaces.map((space) => [space.id, space]));
      const shared = new Set<number>();
      for (let index = 0; index < order.length - 1; index++) {
        const space = byId.get(order[index]);
        const next = byId.get(order[index + 1]);
        const pin = shownPins.get(order[index]);
        if (space && next && space.profileId === next.profileId && pin !== undefined && pin === shownPins.get(order[index + 1])) {
          shared.add(index);
        }
      }
      this.#shared = shared;
    }

    /** Where the strip stands at `position` with shared places counted once; beyond the ends it keeps its distance. */
    place(position: number): number {
      if (this.#shared.size === 0 || this.ids.length === 0) return position;
      const clamped = Math.min(Math.max(position, 0), this.ids.length - 1);
      const lower = Math.floor(clamped);
      let reached = lower - [...this.#shared].filter((index) => index < lower).length;
      if (!this.#shared.has(lower)) reached += clamped - lower;
      return reached + position - clamped;
    }

    /** How many cards toward the trailing edge the card at `index` stands at `position`. */
    offset(index: number, position: number): number {
      if (this.place(index) === this.place(position)) return 0;
      return this.place(placedIndex(index, position, this.ids.length)) - this.place(position);
    }

    /**
     * Where pages fade: the card at the position whole, and between two, the
     * one the strip moves toward fading in over the one it leaves, which stays
     * whole until halfway and then fades away under it.
     */
    opacity(index: number, position: number, origin: number): number {
      const distance = Math.abs(this.offset(index, position));
      if (distance >= 1) return 0;
      return this.#leaves(index, origin, position) ? Math.min(1, 2 * (1 - distance)) : 1 - distance;
    }

    /** The card the strip leaves beneath, the others above it, nearest on top. */
    stacking(index: number, position: number, origin: number): number {
      if (this.#leaves(index, origin, position)) return 0;
      return 2 - Math.abs(this.offset(index, position));
    }

    /** Whether the card at `index` shares its place with the shown Space's while the strip moves. */
    yieldsPlace(index: number, selected: number): boolean {
      if (this.#shared.size === 0 || selected < 0 || selected === index) return false;
      return this.place(index) === this.place(selected);
    }

    #leaves(index: number, origin: number, position: number): boolean {
      if (origin < 0) return this.offset(index, position) < 0;
      return this.place(index) === this.place(origin);
    }
  }
</script>

<script lang="ts">
  import { type Snippet, untrack } from "svelte";
  import type { Attachment } from "svelte/attachments";

  import { readsLight } from "../../branding";
  import { useSpacePager } from "../space-pager";
  import PlaceProvider from "./PlaceProvider.svelte";

  /**
   * The window's page area, as the Mac's SpaceContentPagerView: each Space's
   * page card side by side across the whole content area, moving with the
   * sidebar's pages on the Space pager's clock. The shown Space's card is the
   * live one; a slide shows the card of the Space it moves to or from as a
   * still preview, a card coming on screen showing its page's still where it
   * has one (`page-stills.ts`), and no card takes the pointer until the strip
   * rests. The shown Space's neighbours wait drawn beneath it, unseen, so a
   * slide moves cards the compositor already holds.
   * Neighbouring Spaces that show the same pinned tab count as one place, so
   * moving between them moves no card. Where pages don't slide, the cards keep
   * their place and fade into one another instead.
   */
  let { spaces, liveId, shownPins, embedsPages, onRest, render, children }: {
    spaces: readonly SpaceState[];
    /** Whether cards embed their pages' surfaces, as inside Crest's own window. */
    embedsPages: boolean;
    /** The Space the window shows, whose card is the live one. */
    liveId: string;
    /** The pinned tab each Space shows, for the Spaces that show one. */
    shownPins: ReadonlyMap<string, string>;
    /** Hands the keyboard to the live card when the strip rests with nothing else holding it. */
    onRest: () => void;
    render: Snippet<[space: SpaceState, live: boolean]>;
    /** What lies over the page area, wherever the strip stands, such as a Peek. */
    children?: Snippet;
  } = $props();

  const frame = $derived(useSpacePager());
  const moving = $derived(frame.phase !== "idle");
  const pages = new Map<string, HTMLDivElement>();
  // Read afresh as the pager changes phase, as the person may have changed it meanwhile.
  const slides = $derived((useSpacePager(), slidesPages()));

  // A card can't take the keyboard while the strip moves it, so the one the
  // strip settles on takes it then, as a page the window comes to show does.
  let wasMoving = false;
  $effect(() => {
    const now = moving;
    untrack(() => {
      if (wasMoving && !now) {
        const active = document.activeElement;
        if (!active || active === document.body) onRest();
      }
      wasMoving = now;
    });
  });

  // Where cards fade, a change of Space the pager doesn't move for, as under
  // Reduce Motion, dissolves the card it leaves into the one it shows over a
  // page's settle.
  let dissolving = $state.raw<{ from: string; generation: number } | null>(null);
  const dissolve = $derived(slides ? null : frame.dissolve);
  $effect(() => {
    const next = dissolve;
    if (!next || next.generation === untrack(() => dissolving?.generation)) return;
    dissolving = next;
    const timer = setTimeout(() => {
      if (dissolving?.generation === next.generation) dissolving = null;
    }, 280);
    return () => clearTimeout(timer);
  });

  const leaving = $derived(dissolving && dissolving.from !== liveId ? dissolving.from : null);
  const shown = $derived([...new Set([...frame.pages, liveId, ...(leaving ? [leaving] : []), ...frame.prepared])]
    .map((id) => spaces.find((space) => space.id === id))
    .filter((space): space is SpaceState => !!space));
  const shownIds = $derived(shown.map((space) => space.id).join());
  const pins = $derived([...shownPins].join());

  // A card that comes on screen lets its page take its place first, unseen
  // beneath the others: an embedded page draws only the part of itself it
  // saw on screen when it last laid out, and a card moves without laying
  // out, so a page that came beyond the area's edge would slide in blank.
  // The slide waits at its start meanwhile: drawn in place, the card is
  // rasterized before it moves, rather than in the slide's first frames,
  // which an integrated GPU then draws late.
  const warming = new Map<string, HTMLDivElement>();
  const place = (current: PagerFrame) => {
    const strip = new PageStrip(current.order, spaces, shownPins);
    arrange(current, strip, pages, liveId, slides, leaving, warming);
  };
  $effect(() => {
    void [liveId, shownIds, pins, slides, leaving, spaces];
    return untrack(() => spacePager.subscribeFrames((current) => place(current)));
  });
  const warm = (id: string, element: HTMLDivElement) => {
    if (!slides || warming.get(id) === element) return;
    warming.set(id, element);
    const release = spacePager.holdStart();
    // A card mounted for the Space meanwhile warms on its own.
    const stopWarming = () => {
      if (warming.get(id) === element) warming.delete(id);
    };
    const started = performance.now();
    let frames = 0;
    // A page embedded as the card mounted has laid out once the next frame comes.
    let laidOut = !!element.querySelector("embed[data-content-id]");
    const check = () => {
      if (!element.isConnected) {
        stopWarming();
        release();
        return;
      }
      frames += 1;
      // A card is ready once it has drawn in place, and its page, where it
      // shows one rather than its still, has laid out there.
      const expectsPage = embedsPages && !!element.querySelector(".page-card:not(.clear):not(.still)");
      const embedded = !!element.querySelector("embed[data-content-id]");
      if ((frames > 1 && (!expectsPage || laidOut)) || performance.now() - started > 250) {
        stopWarming();
        place(spacePager.frame);
        release();
        return;
      }
      // An embed that came since the last frame has laid out by the next.
      laidOut = embedded;
      requestAnimationFrame(check);
    };
    requestAnimationFrame(check);
  };

  // Each card keeps one attachment while it stands, so Svelte hands it the
  // card only as it mounts and unmounts: an attachment made anew would be
  // handed the card again, which would warm a card already on its way.
  const cardAttachments = new Map<string, Attachment<HTMLDivElement>>();
  const card = (id: string) => {
    let attachment = cardAttachments.get(id);
    if (!attachment) {
      attachment = (element) => untrack(() => {
        // A card that comes beside one already there warms first.
        if (pages.size > 0) warm(id, element);
        pages.set(id, element);
        return () => {
          pages.delete(id);
          cardAttachments.delete(id);
        };
      });
      cardAttachments.set(id, attachment);
    }
    return attachment;
  };
</script>

<div class={["space-content", moving && "moving"]}>
  {#each shown as space (space.id)}
    {@const live = space.id === liveId}
    <!-- Each card wears its own Space's look, a Start Page's palette among it. -->
    <div
      {@attach card(space.id)}
      class={["space-content-page", readsLight(space.settings.look) ? "reads-light" : "reads-dark", live && "live",
        space.id === leaving && "dissolving"]}
      data-space-content={space.id}
      inert={!live || moving}
      aria-hidden={!live || undefined}
    >
      <PlaceProvider id={space.id} waits={!live && space.id !== leaving && !frame.pages.includes(space.id)}>
        {@render render(space, live)}
      </PlaceProvider>
    </div>
  {/each}
  <div class="space-content-overlay">{@render children?.()}</div>
</div>
