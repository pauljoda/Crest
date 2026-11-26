<script lang="ts" module>
  import type { Session } from "../boot";
  import { reader } from "../reactive";
  import { pageStills } from "../spaces/page-stills";

  /** Follows the stills the window keeps. */
  const readStills = reader(pageStills.subscribe, () => pageStills.version);

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

  /** The surface `pageId` embeds as, where the shell has already said, for a card that embeds it at once. */
  export function knownContentId(pageId: string): string | undefined {
    return contentIds.get(pageId);
  }

  /** The surface `pageId` embeds as, asked of the shell once and remembered, or null when it has none. */
  export async function pageContentId(session: Session, pageId: string): Promise<string | null> {
    const known = contentIds.get(pageId);
    if (known) return known;
    const content = await session.shell?.embed(pageId);
    if (content) contentIds.set(pageId, content);
    return content ?? null;
  }

  /** How many motions resize the window's pages frame after frame now. */
  let liveResizes = 0;

  /**
   * Holds the window's pages as resized frame after frame, as the sidebar's
   * morphs and the resize drags do, until the returned function lets go. While
   * any hold stands, the pages' embeds are marked, and the window draws each of
   * a page's sizes without waiting for the page to lay out at it
   * (`desktop-host.patch`): a page too heavy for a frame follows its card's
   * edge a few frames behind instead of holding the motion, showing what it
   * last drew, clipped by the card or with its background beside it.
   */
  export function holdLiveResize(): () => void {
    if (liveResizes++ === 0) markLiveResize(true);
    let held = true;
    return () => {
      if (!held) return;
      held = false;
      if (--liveResizes === 0) markLiveResize(false);
    };
  }

  function markLiveResize(live: boolean) {
    for (const embed of document.querySelectorAll("embed.page-frame")) embed.toggleAttribute("data-live-resize", live);
  }
</script>

<script lang="ts">
  import { motion as tokens } from "@crest/design";
  import { getContext, type Snippet, untrack } from "svelte";

  import type { Timing } from "../motion";
  import type { PageStill } from "../spaces/page-stills";
  import { StripPlace } from "../spaces/SpaceContentStrip";
  import { useSpacePager } from "../spaces/space-pager";
  import { useEngineVersion } from "../use-core";
  import { useCardsSnap } from "./cards-snap";
  import EmbeddedPage from "./EmbeddedPage.svelte";
  import { usePointerHeld } from "./pointer-hold";
  import { cardLayouts } from "./row-motion";

  /**
   * The page card, clipped to Crest's corners. Inside Crest's Chromium it holds
   * the page's own surface, embedded into this document, so the card clips,
   * layers over and animates the page as SwiftUI does the Mac's page view. In
   * an ordinary browser frames stand in, and every live page keeps its frame so
   * moving between tabs keeps each page's state. What the page asks of the
   * person (`children`) layers over it.
   */
  let { session, pageId, startPage, passive = false, focused = true, transition, children }: {
    session: Session;
    /** The page the card shows, or null where the tab shows none. */
    pageId: string | null;
    /** The Start Page the card shows in place of a page, or null. */
    startPage: Snippet | null;
    /** Whether the card is another Space's, drawn still while the Space pager passes it. */
    passive?: boolean;
    /** Whether the card is the one of a split the window's chrome speaks for, which takes the keyboard. */
    focused?: boolean;
    /** How the card moves into a new place: the row's choice, or the window chrome's. */
    transition?: Timing;
    children?: Snippet;
  } = $props();

  // While a drag holds the pointer, the page is covered so the drag keeps its
  // events, and the card follows the sidebar's width at once, as the Mac's
  // resize does without animation.
  const held = $derived(usePointerHeld());
  // A card the Space pager moves keeps its place in the layout: the strip moves it.
  const moving = $derived(useSpacePager().phase !== "idle");
  const originId = $derived(useSpacePager().originId);
  // On a Start Page, and while the tab has no page, the card lets the Space's
  // backdrop through, keeping its edge and shadow, as the Mac's does.
  const clear = $derived(startPage !== null || !pageId);
  let card = $state<HTMLElement>();
  // A slide brings the card on screen; at rest, and through a swipe that may
  // take it away, the window shows its page. A card waiting, drawn unseen,
  // beside the shown Space shows its still and embeds nothing until a slide
  // takes it up: its page may be the one the shown card holds, as a pinned
  // tab two Spaces of a group share.
  const strip = getContext<StripPlace | undefined>(StripPlace);
  const place = $derived(strip?.id ?? null);
  const waiting = $derived(strip?.waits ?? false);
  const arriving = $derived(place !== null && place !== originId && (moving || waiting));
  const shown = $derived(!passive && (!moving || place === originId));

  // The card moves into a new place as Motion's `layout` had it, which the row
  // it stands in plays as it lays the card out (`row-motion.ts`): never while
  // it is another Space's or the pager moves it, and at once while a drag
  // holds the pointer. The sidebar taking its seat or leaving it changes the
  // card's size each frame, without a layout animation: even one of no length
  // draws a frame of the card scaled from its old box. While it moves
  // to a new place, as a split's columns resize, the card gets a compositor
  // layer of its own: moved from script each frame, it would otherwise paint
  // again, its shadow and all, every frame.
  $effect(() => {
    const element = card;
    if (!element) return;
    cardLayouts.set(element, {
      timing: () => (!passive && useSpacePager().phase === "idle" && !useCardsSnap()
        ? (usePointerHeld() ? { duration: 0 } : transition ?? tokens.chrome) : null),
      started: () => element.style.setProperty("will-change", "transform"),
      finished: () => element.style.removeProperty("will-change"),
    });
    return () => cardLayouts.delete(element);
  });

  // The still a card shows while a slide brings it on screen, over its page
  // left asleep, and the still that covers the page once the strip has landed
  // until the page, woken, has drawn. A card the window shows at rest is
  // followed, so its page is pictured as the window is about to leave.
  const stillPageId = $derived(session.shell && !clear ? pageId : null);
  $effect(() => {
    const element = card;
    if (!shown || !stillPageId || !element) return;
    return pageStills.showing(element, stillPageId);
  });
  // A still fits a card of its size; one taken at another size, before the
  // window or the sidebar changed, leaves the card to show its page. One that
  // comes while the card waits beside the shown Space is drawn then, rather
  // than as a slide takes the card up.
  const candidate = $derived(arriving && stillPageId ? (readStills(), pageStills.still(stillPageId)) : null);
  let unfit = $state<string | null>(null);
  const still = $derived(candidate && unfit !== candidate.url ? candidate : null);
  $effect(() => {
    const shownCandidate = candidate;
    const box = card?.getBoundingClientRect();
    if (!shownCandidate || !box) return;
    if (Math.abs(box.width - shownCandidate.width) > 1.5 || Math.abs(box.height - shownCandidate.height) > 1.5) {
      unfit = shownCandidate.url;
    }
  });
  // The still stays over the page as the card lands, until the page has drawn.
  let cover = $state.raw<{ readonly still: PageStill; readonly going: boolean } | null>(null);
  let shownStill: PageStill | null = null;
  $effect(() => {
    const current = still;
    const landing = !arriving;
    untrack(() => {
      if (current) {
        shownStill = current;
        return;
      }
      const landed = shownStill;
      shownStill = null;
      if (landed && landing) cover = { still: landed, going: false };
    });
  });
  $effect(() => {
    const shownCover = cover;
    const id = stillPageId;
    if (!shownCover || shownCover.going || !id) return;
    let current = true;
    void pageStills.drawn(session.core, id).then(() => {
      if (current && cover && !cover.going) cover = { ...cover, going: true };
    });
    return () => {
      current = false;
    };
  });
  // A card that goes, or turns to another page, takes its cover with it.
  $effect(() => {
    void stillPageId;
    cover = null;
  });
  const coverGone = () => {
    cover = null;
  };
  // A still that fades out goes once it has, or soon after should its fade not run.
  $effect(() => {
    if (!cover?.going) return;
    const timer = setTimeout(coverGone, 400);
    return () => clearTimeout(timer);
  });

  /** The development browser's frames for the pages the card keeps: every live page, or its own alone. */
  const framed = (all: boolean) => (useEngineVersion(session), [...(session.engine?.pages.values() ?? [])])
    .filter((page) => (all || page.id === pageId) && page.url);
</script>

<!-- A page's still, at its card's size in CSS pixels, so each of its pixels lands on one of the screen's. -->
{#snippet stillImage(image: PageStill, going: boolean, onGone?: () => void)}
  <img class={`page-still${going ? " going" : ""}`} src={image.url} alt="" draggable={false}
    style:width="{image.width}px" style:height="{image.height}px" ontransitionend={going ? onGone : undefined} />
{/snippet}

<!--
  A development browser's stand-in for embedded pages: frames, which the
  focused card keeps for every live page so moving between tabs keeps each
  page's state, and a split's other cards for their own page alone.
-->
{#snippet framedPages(all: boolean)}
  {#each framed(all) as page (page.id)}
    <iframe
      class="page-frame"
      sandbox="allow-forms allow-scripts"
      src={page.url}
      title={page.url}
      data-hidden={page.id === pageId ? undefined : ""}
      style:visibility={page.id === pageId ? "visible" : "hidden"}
    ></iframe>
  {/each}
{/snippet}

<main bind:this={card} class={`page-card${clear ? " clear" : ""}${passive ? " passive" : ""}${still ? " still" : ""}`}>
  {#if session.shell}
    {#if !waiting}
      <EmbeddedPage {session} {pageId} passive={passive || !focused} asleep={!!still} />
    {/if}
  {:else if !passive}
    {@render framedPages(focused)}
  {/if}
  {#if still}
    {@render stillImage(still, false)}
  {/if}
  {#if cover}
    {@render stillImage(cover.still, cover.going, coverGone)}
  {/if}
  {@render startPage?.()}
  {@render children?.()}
  {#if held}
    <div class="page-cover"></div>
  {/if}
</main>
