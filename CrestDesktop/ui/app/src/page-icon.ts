import { PageIcon } from "@crest/contracts";
import { useEffect, useState } from "react";

import type { Session } from "./boot";

// The icon a page's engine last drew for each tab, as an object URL, so a tab
// keeps its icon after its page unloads, for as long as the window runs.
const byTab = new Map<string, { key: string; url: string }>();

/** The icon the window last drew for a tab, or null, without asking its page again. */
export function cachedTabIcon(tabId: string): string | null {
  return byTab.get(tabId)?.url ?? null;
}

/**
 * The icon a tab shows: the image its page's engine decoded from the site,
 * asked again whenever the core records a new icon address for the tab.
 * The interface never loads a site's image itself; the engine loads it in the
 * page's own profile.
 */
export function useTabIcon(session: Session, tabId: string, pageId: string | null, iconAddress: string | null) {
  const key = pageId && iconAddress ? `${pageId}|${iconAddress}` : null;
  const [url, setUrl] = useState(() => byTab.get(tabId)?.url ?? null);
  useEffect(() => {
    if (!session.shell || !key || !pageId) return;
    if (byTab.get(tabId)?.key === key) return;
    let current = true;
    session.core
      .request(PageIcon({ pageId }))
      .then((answer) => {
        if (!current || !answer.image || answer.image.length === 0) return;
        const previous = byTab.get(tabId);
        const image = URL.createObjectURL(new Blob([answer.image as Uint8Array<ArrayBuffer>], { type: "image/png" }));
        byTab.set(tabId, { key, url: image });
        if (previous) URL.revokeObjectURL(previous.url);
        setUrl(image);
      })
      .catch(() => {});
    return () => {
      current = false;
    };
  }, [session, tabId, pageId, key]);
  return url;
}
