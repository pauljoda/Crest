import { NativeView, type SpaceState, TabSurface, type TabState } from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { getContext, setContext, untrack } from "svelte";
import type { TransitionConfig } from "svelte/transition";

import type { Session } from "../../boot";
import { insideCrest } from "../../environment";
import { reducesMotion, timed } from "../../motion";
import { bundledTabIcons, useTabIcon } from "../../page-icon.svelte";
import { rowPlacement } from "../sidebar-layout";

/**
 * What the Getting Started practice asks of the sidebar it reuses, as the
 * Mac's BrowserGettingStartedPracticeSidebar binds the real rows to the
 * practice: its Space's pins, saved tabs (always shown, under a caption in
 * place of the Space header) and open tabs, with none of the window's
 * address field, Space switcher or lists. New Tab opens the practice's
 * example tab, since its pages never load.
 */
export interface PracticeSidebar {
  readonly openExampleTab: () => void;
}

/**
 * The Mac's BrowserAddressPresentation: the site, without "www." and with
 * its port, over the rest of the address, decoded; an address with no site
 * shows whole, and no address the prompt.
 */
export function addressPresentation(text: string): { domain: string; route: string | null } {
  if (!text) return { domain: "Search or enter website", route: null };
  let url: URL;
  try {
    url = new URL(text);
  } catch {
    return { domain: text, route: null };
  }
  if (!url.hostname) return { domain: text, route: null };
  const host = url.hostname.startsWith("www.") ? url.hostname.slice(4) : url.hostname;
  const detail = `${url.pathname === "/" ? "" : url.pathname}${url.search.length > 1 ? url.search : ""}${url.hash.length > 1 ? url.hash : ""}`;
  let route = detail;
  try {
    route = decodeURIComponent(detail);
  } catch {
    // An address that is not valid percent-encoding shows as it is.
  }
  return { domain: url.port ? `${host}:${url.port}` : host, route: route || null };
}

/** How many tabs a folder holds, in it and in the folders inside it, as the Mac's header counts them. */
export function folderTabCount(space: SpaceState, folderId: string): number {
  const inside = new Set([folderId]);
  for (let grew = true; grew;) {
    grew = false;
    for (const folder of space.folders) {
      if (folder.parentId !== null && inside.has(folder.parentId) && !inside.has(folder.id)) {
        inside.add(folder.id);
        grew = true;
      }
    }
  }
  return space.tabs.filter((tab) => tab.folderId !== null && inside.has(tab.folderId)).length;
}

/** Where a row stands inside the folders and splits that hold it (`rowPlacement`), as its style attribute. */
export function rowStyle(depth: number, inSplit: boolean): string {
  return Object.entries(rowPlacement(depth, inSplit)).map(([name, value]) => `${name}: ${value}`).join("; ");
}

/**
 * The image a tab's icon shows: one bundled for it, as the practice's tabs
 * wear; inside Crest, its page's engine's; in development, the site's.
 * Call during a component's initialization; read `.current`.
 */
export function useTabIconSource(session: Session, tab: () => TabState, pageId: () => string | null): { readonly current: string | null } {
  const engineIcon = useTabIcon(() => ({ session, tabId: tab().id, pageId: pageId(), iconAddress: tab().faviconUrl }));
  return {
    get current() {
      const shown = tab();
      const bundled = bundledTabIcons.get(shown.id);
      if (bundled) return bundled;
      return insideCrest ? engineIcon.current : (shown.faviconUrl ?? (shown.url ? faviconFor(shown.url) : null));
    },
  };
}

/** Whether a tab shows the Getting Started guide, which wears Crest's app icon, as the Mac's does. */
export function isGuide(tab: TabState): boolean {
  return tab.surface === TabSurface.nativeView && tab.nativeView === NativeView.gettingStarted;
}

function faviconFor(url: string): string | null {
  try {
    const { origin, protocol } = new URL(url);
    return protocol.startsWith("http") ? `${origin}/favicon.ico` : null;
  } catch {
    return null;
  }
}

/** Whether Alt is held, which the keys and the pointer both report. Call during a component's initialization. */
export function useAltHeld(): { readonly current: boolean } {
  let held = $state(false);
  $effect(() => {
    const follow = (event: KeyboardEvent | PointerEvent) => {
      held = event.altKey;
    };
    const letGo = () => {
      held = false;
    };
    window.addEventListener("keydown", follow, true);
    window.addEventListener("keyup", follow, true);
    window.addEventListener("pointermove", follow, true);
    window.addEventListener("blur", letGo);
    return () => {
      window.removeEventListener("keydown", follow, true);
      window.removeEventListener("keyup", follow, true);
      window.removeEventListener("pointermove", follow, true);
      window.removeEventListener("blur", letGo);
    };
  });
  return {
    get current() {
      return held;
    },
  };
}

// MARK: - The selection under the shown tab

/** A selection surface where it stood: as drawn, and where its row lays it out. */
interface Surface {
  readonly element: HTMLElement;
  /** Where it is drawn now, partway along a move of its own. */
  readonly drawn: DOMRect;
  /** Where its row lays it out, which its own moves never change. */
  readonly laid: DOMRect;
  /** Whether its row is drawn at all, which a lift carrying it is not. */
  readonly shown: boolean;
}

/** What a row's selection surface takes from the sidebar's. */
export interface TabSelectionSurface {
  /**
   * The surface's going, for `out:` on it: it follows the surface that took
   * its place there, fading as that one comes in, or fades where it stood.
   */
  readonly out: (node: Element) => () => TransitionConfig;
}

const surfaceKey = Symbol("tab-selection");

/**
 * Motion's `layoutId="tab-selection"` in each Space page's own LayoutGroup:
 * the surface under the shown tab's row is one surface on each Space's page.
 * Showing another tab moves it from the row it was under to the new one, on
 * the collection spring, the surface going crossfading into the one coming,
 * as Motion's shared layout does; one whose row went in the same change
 * moves from where that row was. A row that moves keeps its surface moving
 * from where it stood. Where no surface stood it fades in, and one going
 * with none to follow fades where it stood. One coming back after it went
 * comes from where the last one went, as Motion resumes from the surface
 * its group last drew.
 *
 * The sidebar measures each page's surface before it draws a change and
 * again after (`track` reads what changes it); its rows' surfaces take
 * `out` from `tabSelectionSurface()`. Call during the sidebar's
 * initialization.
 */
export function useTabSelectionSurface(root: () => HTMLElement | null, track: () => unknown): void {
  let before = new Map<Element, Surface>();
  // Where each page's surface last stood as it went, which the next one comes from.
  const last = new WeakMap<Element, DOMRect>();
  // Where each surface going moves to, as it follows the one that took its place.
  const followed = new WeakMap<Element, DOMRect>();
  const moving = new WeakMap<Element, Animation>();

  $effect.pre(() => {
    track();
    untrack(() => {
      before = surfaces(root());
    });
  });
  $effect(() => {
    track();
    untrack(() => {
      const was = before;
      before = new Map();
      const now = surfaces(root());
      for (const [page, previous] of was) if (!now.has(page) && previous.shown) last.set(page, previous.drawn);
      for (const [page, surface] of now) {
        const previous = was.get(page);
        if (previous?.element === surface.element) {
          // The same surface, which moves only as its row moves; one a lift hid comes back where it lands.
          if (previous.shown && surface.shown && !sameFrame(previous.laid, surface.laid)) move(surface, previous.drawn, false);
          continue;
        }
        if (!surface.shown) continue;
        if (previous?.shown) {
          moving.get(previous.element)?.cancel();
          followed.set(previous.element, surface.laid);
        }
        move(surface, previous?.shown ? previous.drawn : last.get(page) ?? null, true);
      }
    });
  });

  /** Moves a surface from `from` to where its row lays it out, fading it in if it is new there. */
  function move(surface: Surface, from: DOMRect | null, fades: boolean) {
    const { element, laid } = surface;
    moving.get(element)?.cancel();
    moving.delete(element);
    const { duration, delay, css } = timed(tokens.collection);
    const travels = from !== null && !reducesMotion() && !sameFrame(from, laid);
    if (!travels && !fades) return;
    const frames: Keyframe[] = [{}, {}];
    if (travels) {
      frames[0].transform = transformFrom(from, laid);
      frames[1].transform = "translate(0px, 0px) scale(1, 1)";
    }
    if (fades) {
      frames[0].opacity = 0;
      frames[1].opacity = 1;
    }
    const animation = element.animate(frames, { duration, delay, easing: css });
    moving.set(element, animation);
    animation.onfinish = () => {
      if (moving.get(element) === animation) moving.delete(element);
    };
  }

  const out = (node: Element) => () => {
    const toward = followed.get(node);
    followed.delete(node);
    const { duration, delay, easing } = timed(tokens.collection);
    const from = node.getBoundingClientRect();
    if (!toward || reducesMotion() || !from.width || !from.height) return { duration, delay, easing, css: (t: number) => `opacity: ${t}` };
    const dx = toward.left + toward.width / 2 - (from.left + from.width / 2);
    const dy = toward.top + toward.height / 2 - (from.top + from.height / 2);
    const sx = toward.width / from.width;
    const sy = toward.height / from.height;
    return {
      duration,
      delay,
      easing,
      css: (t: number, u: number) =>
        `opacity: ${t}; transform: translate(${dx * u}px, ${dy * u}px) scale(${1 + (sx - 1) * u}, ${1 + (sy - 1) * u})`,
    };
  };

  setContext<TabSelectionSurface>(surfaceKey, { out });
}

/** The sidebar's selection surface, for a row's: call during the row's initialization. */
export function tabSelectionSurface(): TabSelectionSurface {
  return getContext<TabSelectionSurface | undefined>(surfaceKey) ?? { out: () => () => ({}) };
}

/**
 * Each Space page's selection surface, by page. A surface on its way out
 * (Svelte makes it inert as it goes) is no longer the page's.
 */
function surfaces(root: HTMLElement | null): Map<Element, Surface> {
  const found = new Map<Element, Surface>();
  for (const element of root?.querySelectorAll<HTMLElement>(".row-selection") ?? []) {
    const row = element.parentElement;
    if (element.inert || !row) continue;
    // The surface fills its row, so the row's frame is where it is laid out.
    const laid = row.getBoundingClientRect();
    found.set(element.closest(".space-page") ?? root!, {
      element, drawn: element.getBoundingClientRect(), laid, shown: laid.width > 0 && laid.height > 0,
    });
  }
  return found;
}

function sameFrame(a: DOMRect, b: DOMRect): boolean {
  return Math.abs(a.left - b.left) < 0.5 && Math.abs(a.top - b.top) < 0.5 && Math.abs(a.width - b.width) < 0.5
    && Math.abs(a.height - b.height) < 0.5;
}

/** The transform that draws a surface laid out at `to` where `from` is, about its centre. */
function transformFrom(from: DOMRect, to: DOMRect): string {
  const dx = from.left + from.width / 2 - (to.left + to.width / 2);
  const dy = from.top + from.height / 2 - (to.top + to.height / 2);
  const sx = to.width ? from.width / to.width : 1;
  const sy = to.height ? from.height / to.height : 1;
  return `translate(${dx}px, ${dy}px) scale(${sx}, ${sy})`;
}
