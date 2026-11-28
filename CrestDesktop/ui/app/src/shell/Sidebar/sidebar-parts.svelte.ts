import { NativeView, type SpaceState, TabSurface, type TabState } from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { untrack } from "svelte";

import type { Session } from "../../boot";
import { reducesMotion, timed } from "../../motion";
import { layoutOf } from "../sidebar-drag.svelte";
import { insideCrest } from "../../environment";
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

/** Tabs in a folder, including nested folders and splits, in the core's sidebar order. */
export function folderTabIds(space: SpaceState, folderId: string): string[] {
  const lists = new Map(space.sidebar.lists.map(list => [list.folderId, list.rows]));
  const visited = new Set<string>();
  const ids: string[] = [];
  function walk(id: string) {
    if (visited.has(id)) return;
    visited.add(id);
    for (const row of lists.get(id) ?? []) {
      if (row.kind.opensList) walk(row.id);
      else ids.push(...row.members);
    }
  }
  walk(folderId);
  return ids;
}

/** How many tabs each folder of the Space holds, nested folders and splits included, counted in one walk of the outline. */
export function folderTabCounts(space: SpaceState): ReadonlyMap<string, number> {
  const lists = new Map(space.sidebar.lists.map(list => [list.folderId, list.rows]));
  const counts = new Map<string, number>();
  function count(id: string): number {
    const known = counts.get(id);
    if (known !== undefined) return known;
    // A folder met again inside itself adds nothing.
    counts.set(id, 0);
    let total = 0;
    for (const row of lists.get(id) ?? []) total += row.kind.opensList ? count(row.id) : row.members.length;
    counts.set(id, total);
    return total;
  }
  for (const folder of space.folders) count(folder.id);
  return counts;
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

// MARK: - Rows moving

/**
 * The Mac's motion for the sidebar's rows as they come and go. A folder,
 * group, split or the saved tabs opening or closing moves the rows around it
 * on `disclosure` (BrowserFolderHeaderControl's withAnimation), while what
 * opens fades in and what closes goes: `prepare()` notes
 * where each row of the shown page stands just before the change is asked
 * for. A row coming or going any other way, as a tab closes, reopens or
 * opens, moves the rest on `dragSource`, from where they stood after the
 * last change. Either way each row that moved slides from where it stood
 * once the core's change draws (`version` reads the batch), and each row new
 * there fades in as SwiftUI's insertion does; a lift moves its rows itself
 * (`lifting`). Call during the sidebar's initialization.
 */
export function useRowMotion(page: () => Element | null | undefined, version: () => number, lifting: () => boolean):
  { prepare(): void } {
  let disclosed: Map<HTMLElement, { readonly left: number; readonly top: number }> | null = null;
  let last: Map<HTMLElement, { readonly left: number; readonly top: number }> | null = null;
  $effect(() => {
    version();
    untrack(() => {
      const now = layoutOf(page());
      const before = disclosed ?? last;
      const timing = disclosed ? tokens.disclosure : tokens.dragSource;
      const changed = disclosed !== null || (last !== null && rowsChanged(last, now));
      disclosed = null;
      last = now;
      if (!before || !changed || lifting() || reducesMotion()) return;
      const { duration, delay, css } = timed(timing);
      for (const [element, to] of now) {
        const from = before.get(element);
        if (!from) {
          element.animate([{ opacity: 0 }, { opacity: 1 }], { duration, delay, easing: css });
          continue;
        }
        const dx = from.left - to.left;
        const dy = from.top - to.top;
        if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) continue;
        element.animate([{ transform: `translate(${dx}px, ${dy}px)` }, { transform: "translate(0px, 0px)" }],
          { duration, delay, easing: css, composite: "add" });
      }
    });
  });
  return {
    prepare() {
      disclosed = layoutOf(page());
    },
  };
}

/** Whether a row came or went between two layouts. */
function rowsChanged(before: ReadonlyMap<Element, unknown>, after: ReadonlyMap<Element, unknown>): boolean {
  if (before.size !== after.size) return true;
  for (const element of after.keys()) if (!before.has(element)) return true;
  return false;
}
