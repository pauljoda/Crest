import {
  AnswerExtensionInstall,
  CancelExtensionInstall,
  ChangeExtension,
  EngineKind,
  type EnginePresentation,
  ExtensionChange,
  InstallExtension,
  type Intent,
  OpenTab,
  RefreshStoreListing,
  type SpaceState,
  TabPlacement,
} from "@crest/contracts";
import { CoreRejection, type CrestCore } from "@crest/core-client";

import type { Session } from "./boot";
import { notices } from "./notices";

/**
 * An extension install this window reviews, as the Mac's
 * ChromiumExtensionInstallation: the Space it installs into, the listing it
 * came from, how much of the package has downloaded, and the other Spaces
 * the person chose to install copies in.
 */
export interface ExtensionReview {
  readonly installId: string;
  readonly spaceId: string;
  readonly extensionId: string;
  /** The Chrome Web Store listing that asked, whose button restates itself once the review ends. */
  readonly pageId: string | null;
  /** How much of the package arrived, from 0 through 1, or null before the download reports. */
  readonly downloaded: number | null;
  readonly copySpaceIds: readonly string[];
}

/** A listing's request to remove the extension it is about, which asks first. */
export interface ExtensionRemoval {
  readonly spaceId: string;
  readonly extensionId: string;
  readonly pageId: string | null;
}

/**
 * The window's extension installs and removals, as the Mac's
 * ChromiumExtensionStore keeps them: one review at a time, begun by a
 * Web Store listing or by Settings, answered in the window that began it.
 */
class Extensions {
  review: ExtensionReview | null = null;
  removal: ExtensionRemoval | null = null;
  /** Opens the shown Space's Extensions in Settings; the window sets it. */
  openSettings: () => void = () => {};
  /** Advances whenever an engine says a profile's extensions changed, so lists ask again. */
  revision = 0;
  version = 0;
  #listeners = new Set<() => void>();

  subscribe(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => void this.#listeners.delete(listener);
  }

  #changed() {
    this.version++;
    for (const listener of this.#listeners) listener();
  }

  /**
   * Takes what a page's engine presents about extensions: a listing asking to
   * install or remove its extension, a download's progress, or a profile's
   * extensions changing.
   */
  presented(session: Session, presentation: EnginePresentation) {
    switch (presentation.$kind) {
      case "StoreInstallRequested":
      case "StoreRemovalRequested": {
        // The engine has checked the listing names its own extension; the
        // Space is the listing's own, which the core refuses where it may not.
        const page = session.core.state.pages.get(presentation.pageId);
        if (!page || page.workspaceId !== session.workspaceId) return;
        if (presentation.$kind === "StoreInstallRequested") {
          void this.install(session, presentation.extensionId, page.spaceId, [], presentation.pageId);
        } else {
          this.removal = { spaceId: page.spaceId, extensionId: presentation.extensionId, pageId: presentation.pageId };
          this.#changed();
        }
        return;
      }
      case "ExtensionDownloadProgressed":
        if (this.review?.installId !== presentation.installId) return;
        this.review = { ...this.review, downloaded: presentation.fraction };
        this.#changed();
        return;
      case "ExtensionsChanged":
        this.revision++;
        this.#changed();
        return;
      default:
    }
  }

  /** Begins installing `extensionId` in the Space, with copies in `copySpaceIds`, and shows its review. */
  async install(session: Session, extensionId: string, spaceId: string, copySpaceIds: readonly string[], pageId: string | null = null) {
    if (this.review) {
      // One review at a time: a second listing's button restates itself.
      if (pageId) refreshListing(session.core, pageId);
      return;
    }
    const installId = crypto.randomUUID();
    this.review = { installId, spaceId, extensionId, pageId, downloaded: null, copySpaceIds };
    this.#changed();
    const sent = await send(session, InstallExtension({
      installId, spaceId, engine: EngineKind.chromium, extensionId, copySpaceIds: [], preApproved: false,
    }));
    if (!sent && this.review?.installId === installId) this.dismiss(session);
  }

  /** Chooses the other Spaces the review installs copies in. */
  chooseCopies(spaceIds: readonly string[]) {
    if (!this.review) return;
    this.review = { ...this.review, copySpaceIds: spaceIds };
    this.#changed();
  }

  /** Answers the review's question: install, keeping site access withheld or not, and in the Spaces chosen. */
  accept(session: Session, promptId: string, withholdsSiteAccess: boolean) {
    const review = this.review;
    if (!review) return;
    void send(session, AnswerExtensionInstall({ promptId, accepted: true, withholdsSiteAccess, copySpaceIds: review.copySpaceIds }));
  }

  /** Puts the review away, stopping an install still under way, and restates the listing's button. */
  dismiss(session: Session) {
    const review = this.review;
    if (!review) return;
    this.review = null;
    this.#changed();
    const install = session.core.state.extensionInstalls.get(review.installId);
    if (!install?.stage.hasEnded) void send(session, CancelExtensionInstall({ installId: review.installId }), false);
    if (review.pageId) refreshListing(session.core, review.pageId);
  }

  /** Asks whether to remove an extension from a Space, as its menu's Remove does. */
  askRemoval(spaceId: string, extensionId: string) {
    this.removal = { spaceId, extensionId, pageId: null };
    this.#changed();
  }

  /** Lists every extension again after a change this window made, such as a pin. */
  changedHere() {
    this.revision++;
    this.#changed();
  }

  /** Removes the extension a removal asked about, or leaves it, and restates the listing's button. */
  settleRemoval(session: Session, removes: boolean) {
    const removal = this.removal;
    if (!removal) return;
    this.removal = null;
    this.#changed();
    const done = removes ? change(session, removal.spaceId, removal.extensionId, ExtensionChange.Remove) : Promise.resolve(false);
    void done.then(() => removal.pageId && refreshListing(session.core, removal.pageId));
  }
}

export const extensions = new Extensions();

/** Sends `intent`, telling the person why where the core refuses it, as the Mac's store reports a refusal. */
function send(session: Session, intent: Intent, reportsRefusal = true): Promise<boolean> {
  return session.core.send(intent).then(() => true, (error: unknown) => {
    if (reportsRefusal && error instanceof CoreRejection) {
      notices.post({ message: refusalMessage(error.rejection.$kind), symbol: "exclamationmark.triangle.fill" });
    }
    return false;
  });
}

/** What a refused extension change tells the person. */
function refusalMessage(kind: string): string {
  switch (kind) {
    case "SpaceIsPrivate": return "Private windows don’t run extensions.";
    case "SpaceLocked": return "Unlock this Space to change its extensions.";
    case "ExtensionNotChangeable": return "This extension can’t be changed.";
    default: return "Couldn’t change this extension.";
  }
}

/** Enables, disables, removes, pins or unpins an extension in the Space. */
export function change(session: Session, spaceId: string, extensionId: string, change: ExtensionChange): Promise<boolean> {
  return send(session, ChangeExtension({ spaceId, engine: EngineKind.chromium, extensionId, change }));
}

/** Restates a Chrome Web Store listing's own button from Chromium's registry. */
function refreshListing(core: CrestCore, pageId: string) {
  void core.request(RefreshStoreListing({ pageId })).catch(() => {});
}

/** The Mac's ExtensionCommand destinations: the store, Chromium's manager, its shortcuts, an extension's details. */
export const extensionPages = {
  store: (extensionId?: string) => extensionId ? `https://chromewebstore.google.com/detail/${extensionId}` : "https://chromewebstore.google.com/",
  manage: () => "chrome://extensions/",
  shortcuts: () => "chrome://extensions/shortcuts",
  details: (extensionId: string) => `chrome://extensions/?id=${extensionId}`,
};

/** Opens `address` in a new tab of the Space, shown, as the Mac opens an extension's pages. */
export function openExtensionPage(session: Session, space: SpaceState, address: string) {
  void session.core.send(OpenTab({
    workspaceId: session.workspaceId, windowId: session.windowId, spaceId: space.id, tabId: crypto.randomUUID(),
    content: { address, view: null, title: null }, placement: TabPlacement.current, afterTabId: null, shows: true,
    placesAsNewTab: true, savesInSavedFolder: false,
  })).catch(() => {});
}
