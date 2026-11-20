import {
  type BlockedPopupEvent,
  type BlockedPopupPageState,
  BlockedPopupPageStateStatics,
  type BlockedPopupStatus,
  BlockedPopupTransition,
  BlockedPopupEvent as Events,
  DecideSitePermission,
  type EnginePresentation,
  SetSitePermission,
  ShowBlockedPopups,
  SiteDecision,
  type SiteOrigin,
  SitePermission,
  SitePermissionDecision,
} from "@crest/contracts";
import type { CrestCore } from "@crest/core-client";
import { useSyncExternalStore } from "react";

import { siteOriginOf } from "./site-control";

/** The one blocked pop-up indication a page may show, as the Mac's BrowserBlockedPopupNotice. */
export interface BlockedPopupNotice {
  readonly origin: SiteOrigin;
  readonly status: BlockedPopupStatus;
}

/** The notice's heading, as the Mac's presentation words it. */
export function noticeTitle(notice: BlockedPopupNotice): string {
  return notice.status.offersAllow ? `Pop-up blocked for ${notice.origin.host}` : `Pop-ups allowed for ${notice.origin.host}`;
}

const sameOrigin = (left: SiteOrigin | null, right: SiteOrigin | null) =>
  !!left && !!right && left.scheme === right.scheme && left.host === right.host && left.port === right.port;

/** What a page needs of the window to keep its pop-up state. */
interface PopupPage {
  readonly pageId: string;
  readonly spaceId: string;
  /** The address the page's document has, for a page whose commit this window did not hear. */
  readonly url: string | null;
}

/**
 * The pop-ups each page's engine blocked, and Crest's pop-up choice applied
 * to each page's engine, as the Mac's page keeps them
 * (PlatformPage+BlockedPopups). The core's notice rules
 * (`BlockedPopupTransition`) decide every state, so a page never stacks
 * indications in one document; the core's choice for the site
 * (`SiteDecision`) is what each page's engine enforces (`SetSitePermission`).
 */
class BlockedPopups {
  #states = new Map<string, BlockedPopupPageState>();
  #documents = new Map<string, number>();
  /** Whether each page's engine was last told to allow automatic pop-ups. */
  #applied = new Map<string, boolean>();
  /** Each page's work, in order, so an answer never lands on a newer state. */
  #queues = new Map<string, Promise<void>>();
  #listeners = new Set<() => void>();
  version = 0;

  subscribe = (listener: () => void) => {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  };

  /** The notice the page shows, or null. */
  notice(pageId: string): BlockedPopupNotice | null {
    const state = this.#states.get(pageId);
    return state?.status && state.origin ? { origin: state.origin, status: state.status } : null;
  }

  /** What the page's engine presented, for the pages this window shows. */
  presented(core: CrestCore, presentation: EnginePresentation, page: (pageId: string) => PopupPage | null) {
    switch (presentation.$kind) {
      case "PageNavigationStarted":
        return this.#enqueue(presentation.pageId, () => this.#apply(core, presentation.pageId, Events.navigation));
      case "PageNavigationCommitted": {
        const known = page(presentation.pageId);
        this.#documents.set(presentation.pageId, (this.#documents.get(presentation.pageId) ?? 0) + 1);
        if (!known) return;
        return this.#enqueue(presentation.pageId, () => this.#synchronize(core, known, presentation.url, true));
      }
      case "PopupBlocked": {
        const known = page(presentation.pageId);
        const origin = siteOriginOf(presentation.pageUrl);
        if (!known || !origin) return;
        return this.#enqueue(presentation.pageId, async () => {
          if ((await this.#decision(core, known.spaceId, origin)).grants) return;
          await this.#apply(core, known.pageId, Events.blocked, String(this.#documents.get(known.pageId) ?? 0), origin);
        });
      }
      default:
    }
  }

  /** A Space's choices changed: each page this window shows takes its site's pop-up choice again. */
  permissionsChanged(core: CrestCore, pages: readonly PopupPage[]) {
    for (const page of pages) {
      this.#enqueue(page.pageId, () => this.#synchronize(core, page, page.url, false));
    }
  }

  /**
   * Allows automatic pop-ups for the site whose pop-up the page blocked, in
   * the page's Space, and opens what the engine held, as the Mac's Allow
   * Automatic Pop-ups does.
   */
  allow(core: CrestCore, page: PopupPage) {
    return this.#enqueue(page.pageId, async () => {
      const notice = this.notice(page.pageId);
      if (!notice?.status.offersAllow || !sameOrigin(siteOriginOf(page.url), notice.origin)) return;
      await core.send(DecideSitePermission({
        spaceId: page.spaceId, origin: notice.origin, permission: SitePermission.popups, detail: null,
        decision: SitePermissionDecision.grantPersistently,
      })).catch(() => undefined);
      await this.#synchronize(core, page, page.url, true);
      // The engine kept the pop-ups it blocked and opens them now.
      const opened = await core.request(ShowBlockedPopups({ pageId: page.pageId })).catch(() => false);
      if (opened) await this.#apply(core, page.pageId, Events.popupAllowed);
    });
  }

  /** Applies Crest's pop-up choice for the page's site to its engine, and lets the notice follow it. */
  async #synchronize(core: CrestCore, page: PopupPage, url: string | null, always: boolean) {
    const origin = siteOriginOf(url);
    const allows = origin ? (await this.#decision(core, page.spaceId, origin)).grants : false;
    if (always || this.#applied.get(page.pageId) !== allows) {
      this.#applied.set(page.pageId, allows);
      // An engine's own blocker takes the site's own allowance, and otherwise its default of blocking.
      await core.request(SetSitePermission({ pageId: page.pageId, permission: SitePermission.popups, allowed: allows ? true : null }))
        .catch(() => false);
    }
    const notice = this.notice(page.pageId);
    if (!origin || !notice || !sameOrigin(notice.origin, origin)) return;
    await this.#apply(core, page.pageId, allows ? Events.permissionAllowed : Events.permissionBlockedAgain);
  }

  #decision(core: CrestCore, spaceId: string, origin: SiteOrigin) {
    return core.query(SiteDecision({ spaceId, origin, permission: SitePermission.popups, detail: null }))
      .then((answer) => answer.decision, () => SitePermissionDecision.ask);
  }

  /** The page's state after `event`, as the core's notice rules answer it; nothing changes where they say so. */
  async #apply(core: CrestCore, pageId: string, event: BlockedPopupEvent, documentIdentifier: string | null = null,
    origin: SiteOrigin | null = null) {
    const state = this.#states.get(pageId) ?? BlockedPopupPageStateStatics.empty;
    const answer = await core.query(BlockedPopupTransition({ state, event, documentIdentifier, origin })).catch(() => null);
    if (!answer?.state) return;
    this.#states.set(pageId, answer.state);
    this.version++;
    for (const listener of this.#listeners) listener();
  }

  #enqueue(pageId: string, work: () => Promise<void>): Promise<void> {
    const next = (this.#queues.get(pageId) ?? Promise.resolve()).then(work, work);
    this.#queues.set(pageId, next.catch(() => undefined));
    return next;
  }
}

/** This window's blocked pop-ups. */
export const blockedPopups = new BlockedPopups();

/** Redraws with the window's blocked pop-ups. */
export function useBlockedPopups(): BlockedPopups {
  useSyncExternalStore(blockedPopups.subscribe, () => blockedPopups.version);
  return blockedPopups;
}
