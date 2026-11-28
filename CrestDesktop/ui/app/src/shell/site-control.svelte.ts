import {
  type BrowsingDataCategory,
  ContentBlockingApplies,
  DecideSitePermission,
  DeleteSiteData,
  PageCertificates,
  type PageState,
  SiteDecision,
  type SiteOrigin,
  SetSiteContentBlocking,
  SitePermission,
  type SitePermissionDecision,
  type SpaceState,
  type WebsiteDataRead,
  WebScheme,
} from "@crest/contracts";
import type { CrestCore } from "@crest/core-client";
import { untrack } from "svelte";

import type { Session } from "../boot";
import { notices } from "../notices";
import { coreState } from "../use-core";

/**
 * The origin of an address with a scheme and a host, as the Mac's
 * SiteOrigin(url:) makes it, lowercased and with the scheme's default port
 * where it names none; null for one without a host, such as a file.
 */
export function siteOriginOf(address: string | null): SiteOrigin | null {
  if (!address) return null;
  try {
    const url = new URL(address);
    const scheme = url.protocol.replace(/:$/, "").toLowerCase();
    const host = url.hostname.toLowerCase().replace(/^\[(.*)\]$/, "$1");
    if (!host) return null;
    const port = url.port ? Number(url.port) : WebScheme.named(scheme)?.defaultPort ?? 0;
    return { scheme, host, port };
  } catch {
    return null;
  }
}

/** The host an address names, or null. */
export function hostOf(address: string | null): string | null {
  try {
    return address ? new URL(address).hostname || null : null;
  } catch {
    return null;
  }
}

/** What the settings call `decision` for `permission`: Ask reads as what the site gets before the person answers. */
export function permissionTitle(permission: SitePermission, decision: SitePermissionDecision): string {
  return decision.asks ? permission.askTitle : decision.title;
}

/** A site as one Space sees it, which the site hooks ask the core about. */
export interface SiteInSpace {
  readonly session: Session;
  readonly spaceId: string;
  readonly origin: SiteOrigin | null;
}

/** An origin as the key the hooks ask again by. */
function originKey(origin: SiteOrigin | null): string {
  return origin ? `${origin.scheme}://${origin.host}:${origin.port}` : "";
}

/**
 * The choice that answers each permission for `origin` in the Space, as the
 * core answers it (`SiteDecision`), asked again whenever a Space's choices
 * change. Null until the answers arrive.
 */
export function useSiteDecisions(site: () => SiteInSpace): { readonly current: ReadonlyMap<string, SitePermissionDecision> | null } {
  // The answers keep the site they are for, so another site's never show.
  let decisions = $state.raw<{ readonly key: string; readonly answers: ReadonlyMap<string, SitePermissionDecision> } | null>(null);
  const key = $derived(`${site().spaceId}|${originKey(site().origin)}`);
  // The origin is its key, asked again whenever a Space's choices change.
  const asked = $derived(`${key}|${coreState(site().session).sitePermissionRevision}`);
  $effect(() => {
    void asked;
    return untrack(() => {
      const { session, spaceId, origin } = site();
      const askedKey = key;
      if (!origin) {
        decisions = null;
        return;
      }
      let current = true;
      void Promise.all(SitePermission.all.map(async (permission) => [permission.name,
        (await session.core.query(SiteDecision({ spaceId, origin, permission, detail: null }))).decision] as const))
        .then((answers) => {
          if (current) decisions = { key: askedKey, answers: new Map(answers) };
        }, () => undefined);
      return () => {
        current = false;
      };
    });
  });
  return {
    get current() {
      return decisions?.key === key ? decisions.answers : null;
    },
  };
}

/**
 * The Mac's SiteContentBlockingSwitch for `origin` in the Space: null where
 * none is offered, a page that shows no website or a Space that blocks
 * nothing, else whether the Space blocks ads and trackers on the site now,
 * asked again whenever the lists or the sites with blocking off change.
 */
export function useSiteContentBlocking(site: () => SiteInSpace): { readonly current: boolean | null } {
  // The answer keeps the site it is for: a site's last answer stands while
  // it is asked again, and another site's never shows.
  let blocks = $state.raw<{ readonly key: string; readonly blocks: boolean | null } | null>(null);
  const filterLists = $derived(coreState(site().session).filterLists);
  const blockingSites = $derived(coreState(site().session).blockingSites);
  // The origin is its key, asked again whenever the lists or the sites with blocking off change.
  const asked = $derived(`${site().spaceId}|${originKey(site().origin)}`);
  $effect(() => {
    void asked;
    void filterLists;
    void blockingSites;
    return untrack(() => {
      const { session, spaceId, origin } = site();
      const askedKey = asked;
      if (!origin || (origin.scheme !== "http" && origin.scheme !== "https")) {
        blocks = null;
        return;
      }
      let current = true;
      void (async () => {
        const applies = await session.core.query(ContentBlockingApplies({ spaceId, origin: null }));
        const onSite = applies && await session.core.query(ContentBlockingApplies({ spaceId, origin }));
        if (current) blocks = { key: askedKey, blocks: applies ? onSite : null };
      })().catch(() => {
        if (current) blocks = null;
      });
      return () => {
        current = false;
      };
    });
  });
  return {
    get current() {
      return blocks?.key === asked ? blocks.blocks : null;
    },
  };
}

/** Turns ad blocking on or off for `origin`, from the Space the person did it in; on again, it holds everywhere. */
export function setSiteContentBlocking(core: CrestCore, spaceId: string, origin: SiteOrigin, blocks: boolean): Promise<boolean> {
  return core.send(SetSiteContentBlocking({ spaceId, origin, blocks })).then(() => true, () => false);
}

/**
 * The Mac's Toggle Content Blocking: turns blocking off, or on again, for
 * the site of `page` in its Space, and reloads the page so the change shows.
 * Nothing happens for a page that shows no website or a Space that blocks
 * nothing.
 */
export async function toggleSiteContentBlocking(core: CrestCore, spaceId: string, address: string | null, reload: () => void) {
  const origin = siteOriginOf(address);
  if (!origin || (origin.scheme !== "http" && origin.scheme !== "https")) return;
  if (!(await core.query(ContentBlockingApplies({ spaceId, origin: null })))) return;
  const blocks = await core.query(ContentBlockingApplies({ spaceId, origin }));
  if (await setSiteContentBlocking(core, spaceId, origin, !blocks)) reload();
}

/** Sets the choice for `permission` on `origin` in the Space, as the person picked it. */
export function decide(core: CrestCore, spaceId: string, origin: SiteOrigin, permission: SitePermission,
  decision: SitePermissionDecision) {
  void core.send(DecideSitePermission({ spaceId, origin, permission, detail: null, decision })).catch(() => undefined);
}

/**
 * The certificate chain the page's engine verified its HTTPS document with,
 * leaf first (`PageCertificates`), or none: a certificate is offered for
 * review only where there is one, as on the Mac.
 */
export function useCertificates(source: () => { readonly session: Session; readonly page: PageState | null }): { readonly current: readonly Uint8Array[] } {
  // The chain keeps the document it is for, so a document that has gone,
  // or one still being asked about, offers none.
  let chain = $state.raw<{ readonly document: string; readonly certificates: readonly Uint8Array[] } | null>(null);
  // The page's document and its security are what change its chain.
  const shownDocument = $derived.by(() => {
    const { page } = source();
    return page ? `${page.id}|${page.live.url ?? ""}|${page.live.security.name}` : "";
  });
  // A load that ends asks again, as a reload of the same address commits
  // another document whose chain may differ.
  const asked = $derived(`${shownDocument}|${source().page?.live.isLoading ?? false}`);
  $effect(() => {
    void asked;
    return untrack(() => {
      const { session, page } = source();
      const askedDocument = shownDocument;
      const https = page?.live.url?.toLowerCase().startsWith("https:") ?? false;
      if (!page || !https || !session.shell) {
        chain = null;
        return;
      }
      let current = true;
      void session.core.request(PageCertificates({ pageId: page.id })).then(
        (answer) => {
          if (current) chain = { document: askedDocument, certificates: answer.certificates };
        },
        () => {
          if (current) chain = null;
        },
      );
      return () => {
        current = false;
      };
    });
  });
  return {
    get current() {
      return chain?.document === shownDocument ? chain.certificates : [];
    },
  };
}

/**
 * Clears what the page's site keeps in `category` in the page's Space,
 * reloads the page and says how it went, as the Mac's clearSiteData does.
 */
export async function clearSiteData(session: Session, page: PageState, space: SpaceState, category: BrowsingDataCategory,
  ephemeral: boolean, reload: () => void) {
  const host = hostOf(page.live.url);
  if (!host) return;
  const requestId = crypto.randomUUID();
  const { core } = session;
  let cleared = false;
  try {
    await core.send(DeleteSiteData({ requestId, profileId: space.profileId, ephemeral, hosts: [host], categories: [category] }));
    cleared = await deletion(core, requestId);
  } catch {
    cleared = false;
  }
  reload();
  const title = (cleared ? category.clearedTitle : category.failedTitle) ?? category.title;
  notices.post({ message: title, symbol: cleared ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" });
}

/** How long a deletion may take before it counts as not done. */
const deletionWait = 60_000;

/** Whether the deletion `requestId` erased everything, once the core says it finished. */
export function deletion(core: CrestCore, requestId: string): Promise<boolean> {
  return answer(core, core.state.deletions, requestId).then((deleted) => deleted ?? false);
}

/** The sites the read `requestId` found, once the core lists them, or null when it never does. */
export function websiteData(core: CrestCore, requestId: string): Promise<WebsiteDataRead | null> {
  return answer(core, core.state.websiteDataReads, requestId);
}

/** What the core answers `requestId` with in `answers`, taken out once it does, or null after the wait. */
function answer<T>(core: CrestCore, answers: Map<string, T>, requestId: string): Promise<T | null> {
  return new Promise((resolve) => {
    const settle = () => {
      if (!answers.has(requestId)) return false;
      const found = answers.get(requestId) as T;
      answers.delete(requestId);
      stop();
      clearTimeout(timer);
      resolve(found);
      return true;
    };
    const stop = core.state.subscribe(settle);
    const timer = setTimeout(() => {
      stop();
      resolve(null);
    }, deletionWait);
    settle();
  });
}
