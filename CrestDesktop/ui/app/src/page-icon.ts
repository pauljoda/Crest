import { PageIcon } from "@crest/contracts";
import { useEffect, useState } from "react";

import type { Session } from "./boot";
import { storedTabIcon, storeTabIcon } from "./tab-icon-store";

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
  return byTab.get(tabId)?.url ?? null;
}

/**
 * The icon a tab shows: the image its page's engine decoded from the site,
 * asked again whenever the core records a new icon address for the tab.
 * Until its page draws one, a tab shows the image it last wore for that
 * address, from before a relaunch too. The interface never loads a site's
 * image itself; the engine loads it in the page's own profile.
 */
export function useTabIcon(session: Session, tabId: string, pageId: string | null, iconAddress: string | null) {
  const key = pageId && iconAddress ? `${pageId}|${iconAddress}` : null;
  // A restored tab already knows its icon's address, so its page is asked as
  // it opens, before its engine holds the image; it is asked again once the
  // page has loaded, since the engine doesn't report an icon the tab has.
  const page = pageId ? session.core.state.pages.get(pageId) : undefined;
  const settled = page?.phase.name === "live" && !page.live.isLoading;
  const [url, setUrl] = useState(() => byTab.get(tabId)?.url ?? null);
  // A tab the window hasn't drawn an icon for yet wears the one it kept; a
  // view of a tab another view already drew takes that view's.
  useEffect(() => {
    const known = byTab.get(tabId);
    if (known) {
      setUrl(known.url);
      return;
    }
    if (!session.shell || !iconAddress) return;
    let current = true;
    void storedTabIcon(tabId, iconAddress).then((image) => {
      if (!current) return;
      const drawn = byTab.get(tabId);
      if (drawn) setUrl(drawn.url);
      else if (image) setUrl(adopt(tabId, `stored|${iconAddress}`, image));
    });
    return () => {
      current = false;
    };
  }, [session, tabId, iconAddress]);
  useEffect(() => {
    if (!session.shell || !key || !pageId || !iconAddress) return;
    if (byTab.get(tabId)?.key === key) return;
    let current = true;
    session.core
      .request(PageIcon({ pageId }))
      .then((answer) => {
        if (!current || !answer.image || answer.image.length === 0) return;
        setUrl(adopt(tabId, key, answer.image));
        void storeTabIcon(tabId, iconAddress, answer.image);
      })
      .catch(() => {});
    return () => {
      current = false;
    };
  }, [session, tabId, pageId, key, iconAddress, settled]);
  return url;
}
