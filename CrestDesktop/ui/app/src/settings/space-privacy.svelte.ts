import {
  BrowsingDataCategory,
  BrowsingDataRange,
  DeleteBrowsingData,
  DeleteSiteData,
  type Intent,
  ReadWebsiteData,
  type SpaceState,
  type StoredSite,
} from "@crest/contracts";
import { CoreRejection } from "@crest/core-client";
import { untrack } from "svelte";

import type { Session } from "../boot";
import { deletion, websiteData } from "../shell/site-control.svelte";

/**
 * What a Space's privacy sections share: sending what they change, naming
 * what they list, and the sites that keep data in the Space's profile.
 */

export function send(session: Session, intent: Intent) {
  return session.core.send(intent).then(() => true, () => false);
}

/** Words joined as a list in the person's language: "History, Cookies and Site Data, and Cached Images and Files". */
export function listed(words: readonly string[]): string {
  return new Intl.ListFormat(navigator.language, { type: "conjunction" }).format(words);
}

/** Whether the window browses privately, so its profiles keep data only in memory. */
export function ephemeral(session: Session) {
  return session.core.state.workspaces.get(session.workspaceId)?.kind.isPrivate ?? false;
}

/** BrowserWebsiteDataList: the sites that keep data in the Space's profile, as every engine lists them. */
export interface WebsiteData {
  /** The sites, sorted by name, or null until the first listing ends. */
  readonly sites: readonly StoredSite[] | null;
  /** Every engine listed its own sites; one that could not may hide some. */
  readonly complete: boolean;
  /** The Space is locked, so its sites stay hidden. */
  readonly locked: boolean;
  readonly removing: boolean;
  /** The last removal left something an engine could not clear. */
  readonly removalFailed: boolean;
  readonly read: () => void;
  readonly remove: (sites: readonly StoredSite[]) => void;
  readonly removeAll: () => void;
}

interface Listing {
  readonly profileId: string;
  readonly sites: readonly StoredSite[] | null;
  readonly complete: boolean;
  readonly locked: boolean;
}

/** The sites that keep data in `space`'s profile, listed again as its profile changes. Call during initialization. */
export function useWebsiteData(session: () => Session, space: () => SpaceState): WebsiteData {
  const profileId = $derived(space().profileId);
  let listing = $state.raw<Listing>({ profileId: space().profileId, sites: null, complete: true, locked: false });
  let removing = $state(false);
  let removalFailed = $state(false);
  // Only the newest read lands, so an older one that finishes later never puts back what it found.
  let latest = "";
  const read = () => {
    const requested = profileId;
    const requestId = crypto.randomUUID();
    latest = requestId;
    session().core.send(ReadWebsiteData({ requestId, profileId: requested, ephemeral: ephemeral(session()), host: null }))
      .then(() => websiteData(session().core, requestId))
      .then((found) => {
        if (latest !== requestId || profileId !== requested) return;
        const previous = listing;
        listing = {
          profileId: requested,
          sites: found ? [...found.sites].sort((left, right) => left.site.localeCompare(right.site)) : (previous.profileId === requested ? previous.sites : null) ?? [],
          complete: found?.complete ?? false,
          locked: false,
        };
      }, (error: unknown) => {
        if (latest !== requestId || profileId !== requested) return;
        const locked = error instanceof CoreRejection && error.rejection.$kind === "SpaceLocked";
        listing = { profileId: requested, sites: [], complete: false, locked };
      });
  };
  $effect(() => {
    void profileId;
    untrack(() => {
      removalFailed = false;
      read();
    });
  });
  const removingWith = (request: Intent & { requestId: string }) => {
    if (removing) return;
    removing = true;
    void session().core.send(request).then(() => deletion(session().core, request.requestId), () => false).then((deleted) => {
      removalFailed = !deleted;
      removing = false;
      read();
    });
  };
  const bySite = BrowsingDataCategory.all.filter((category) => category.clearsBySite);
  const shown = $derived(listing.profileId === profileId ? listing : { sites: null, complete: true, locked: false });
  return {
    get sites() {
      return shown.sites;
    },
    get complete() {
      return shown.complete;
    },
    get locked() {
      return shown.locked;
    },
    get removing() {
      return removing;
    },
    get removalFailed() {
      return removalFailed;
    },
    read,
    remove: (sites) => sites.length > 0 && removingWith(DeleteSiteData({
      requestId: crypto.randomUUID(), profileId, ephemeral: ephemeral(session()), hosts: sites.map((site) => site.site), categories: bySite,
    })),
    removeAll: () => removingWith(DeleteBrowsingData({
      requestId: crypto.randomUUID(), profileId, ephemeral: ephemeral(session()), range: BrowsingDataRange.allTime, categories: bySite,
    })),
  };
}
