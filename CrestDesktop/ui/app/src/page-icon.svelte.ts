import { PageIcon } from "@crest/contracts";
import { untrack } from "svelte";

import type { Session } from "./boot";
import { storedTabIcon, storeTabIcon } from "./tab-icon-store";
import { useCoreVersion } from "./use-core";

// The icon a page's engine last drew for each tab, as an object URL, so a tab
// keeps its icon after its page unloads, for as long as the window runs; the
// icon store keeps it across launches.
const byTab = new Map<string, { key: string; url: string }>();

// An image another view of the same tab, such as a split's icon stack, may
// still show stays valid; a tab's few images live as long as the window.
function adopt(tabId: string, key: string, image: Uint8Array): string {
  const url = URL.createObjectURL(new Blob([image as Uint8Array<ArrayBuffer>], { type: "image/png" }));
  byTab.set(tabId, { key, url });
  return url;
}

/**
 * Icons bundled for tabs whose pages never load, by tab: the Getting Started
 * practice's tabs wear the marks shipped for them, as a loaded page would
 * leave them, where the Mac's practice sets each tab's favicon.
 */
export const bundledTabIcons = new Map<string, string>();

/** The icon the window last drew for a tab, or null, without asking its page again. */
export function cachedTabIcon(tabId: string): string | null {
  return bundledTabIcons.get(tabId) ?? byTab.get(tabId)?.url ?? null;
}

/** What a view of a tab shows its icon from. */
export interface TabIconSource {
  readonly session: Session;
  readonly tabId: string;
  readonly pageId: string | null;
  readonly iconAddress: string | null;
}

/**
 * The icon a tab shows: the image its page's engine decoded from the site,
 * asked again whenever the core records a new icon address for the tab.
 * Until its page draws one, a tab shows the image it last wore for that
 * address, from before a relaunch too. The interface never loads a site's
 * image itself; the engine loads it in the page's own profile.
 *
 * Answers it as an object URL, or null while there is none:
 * `const icon = useTabIcon(() => ({ session, tabId, pageId, iconAddress }))`,
 * then `icon.current`. Call during a component's initialization.
 */
export function useTabIcon(source: () => TabIconSource): { readonly current: string | null } {
  let url = $state(byTab.get(untrack(source).tabId)?.url ?? null);
  // A restored tab already knows its icon's address, so its page is asked as
  // it opens, before its engine holds the image; it is asked again once the
  // page has loaded, since the engine doesn't report an icon the tab has.
  const settled = $derived.by(() => {
    const { session, pageId } = source();
    if (!pageId) return false;
    useCoreVersion(session);
    const page = session.core.state.pages.get(pageId);
    return page?.phase.name === "live" && !page.live.isLoading;
  });
  // A tab the window hasn't drawn an icon for yet wears the one it kept; a
  // view of a tab another view already drew takes that view's.
  $effect(() => {
    const { session, tabId, iconAddress } = source();
    const known = byTab.get(tabId);
    if (known) {
      url = known.url;
      return;
    }
    if (!session.shell || !iconAddress) return;
    let current = true;
    void storedTabIcon(tabId, iconAddress).then((image) => {
      if (!current) return;
      const drawn = byTab.get(tabId);
      if (drawn) url = drawn.url;
      else if (image) url = adopt(tabId, `stored|${iconAddress}`, image);
    });
    return () => {
      current = false;
    };
  });
  $effect(() => {
    const { session, tabId, pageId, iconAddress } = source();
    void settled;
    const key = pageId && iconAddress ? `${pageId}|${iconAddress}` : null;
    if (!session.shell || !key || !pageId || !iconAddress) return;
    if (byTab.get(tabId)?.key === key) return;
    let current = true;
    session.core
      .request(PageIcon({ pageId }))
      .then((answer) => {
        if (!current || !answer.image || answer.image.length === 0) return;
        url = adopt(tabId, key, answer.image);
        void storeTabIcon(tabId, iconAddress, answer.image);
      })
      .catch(() => {});
    return () => {
      current = false;
    };
  });
  return {
    get current() {
      return url;
    },
  };
}
