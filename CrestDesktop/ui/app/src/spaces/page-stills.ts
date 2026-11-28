import { CapturePage, type PageCaptured } from "@crest/contracts";
import type { CrestCore } from "@crest/core-client";

/** A page as its card last showed it, at the card's size in CSS pixels, drawn at the screen's own pixels. */
export interface PageStill {
  readonly url: string;
  readonly width: number;
  readonly height: number;
}

/** A capture this window asked for: a still to keep, or a page's first frame to wait for. */
type Asked =
  | { readonly kind: "still"; readonly pageId: string; readonly width: number; readonly height: number; readonly at: number }
  | { readonly kind: "drawn"; readonly done: () => void };

/** How many stills the window keeps, the latest first. */
const kept = 6;

/** How long a picture asked for holds off another of the same page, should its answer never come. */
const stillTimeout = 3000;

/** How long a page may take to draw once it wakes before its still goes anyway. */
const drawnTimeout = 1000;

/**
 * Still pictures of the pages the window's cards show, for the Space pager.
 * Chromium lets go of what a hidden page has drawn, so a page coming back on
 * screen draws itself again, which an integrated GPU can't fit between the
 * frames of a slide. So the pages the window shows are pictured whole as it
 * is about to leave their Space, and the card that brings one back slides in
 * as that picture with the page left asleep; the page wakes once the strip
 * has landed, and the picture goes once the page has drawn. The window keeps the
 * latest few, in memory only.
 */
class PageStills {
  /** Each still with its picture and when it was asked for, so an older capture never replaces a newer one. */
  #stills = new Map<string, PageStill & { readonly image: HTMLImageElement; readonly askedAt: number }>();
  #asked = new Map<string, Asked>();
  #shown = new Map<HTMLElement, string>();
  #listeners = new Set<() => void>();
  #version = 0;

  /** Counts the stills kept, so a card waiting beside the shown Space draws one that comes after it did. */
  get version(): number {
    return this.#version;
  }

  subscribe = (listener: () => void) => {
    this.#listeners.add(listener);
    return () => void this.#listeners.delete(listener);
  };

  /** Follows a card the window shows its page in, at rest, until it goes. */
  showing(card: HTMLElement, pageId: string): () => void {
    this.#shown.set(card, pageId);
    return () => {
      if (this.#shown.get(card) === pageId) this.#shown.delete(card);
    };
  }

  /**
   * Pictures every page the window shows, as it is about to ask the core for
   * another Space. Asked first, the pictures are taken while the pages still
   * show: the core hides a page the window leaves, and a slide's first frame
   * moves its card, after which a hidden page draws no frame to take one from.
   */
  leaving(core: CrestCore) {
    for (const [card, pageId] of this.#shown) {
      const box = card.getBoundingClientRect();
      if (box.width > 0 && box.height > 0) this.capture(core, pageId, box.width, box.height);
    }
  }

  /** Asks the page's engine for a picture of all of it, at the card's size in CSS pixels. */
  capture(core: CrestCore, pageId: string, width: number, height: number) {
    const now = performance.now();
    for (const [captureId, asked] of this.#asked) {
      if (asked.kind !== "still") continue;
      // A picture still on its way stands; one whose answer never came gives way.
      if (now - asked.at > stillTimeout) this.#asked.delete(captureId);
      else if (asked.pageId === pageId) return;
    }
    const captureId = crypto.randomUUID();
    this.#asked.set(captureId, { kind: "still", pageId, width, height, at: now });
    const forget = () => this.#asked.delete(captureId);
    // A width of nothing takes the picture at the page's own pixels.
    void core.request(CapturePage({ pageId, captureId, area: null, width: 0 }))
      .then((accepted) => accepted || forget(), forget);
  }

  /**
   * Waits until the page has drawn a frame since it woke: the engine takes a
   * picture of a page from its next frame, so a picture of one pixel comes
   * once there is one, or after a second if none comes.
   */
  drawn(core: CrestCore, pageId: string): Promise<void> {
    return new Promise((resolve) => {
      const captureId = crypto.randomUUID();
      const done = () => {
        clearTimeout(timer);
        this.#asked.delete(captureId);
        resolve();
      };
      const timer = setTimeout(done, drawnTimeout);
      this.#asked.set(captureId, { kind: "drawn", done });
      void core.request(CapturePage({ pageId, captureId, area: { x: 0, y: 0, width: 1, height: 1 }, width: 1 }))
        .then((accepted) => accepted || done(), done);
    });
  }

  /** Takes a capture this window asked for: keeps a still once it's decoded, or lets a wait for a frame end. */
  received(captured: PageCaptured) {
    const asked = this.#asked.get(captured.captureId);
    if (!asked) return;
    this.#asked.delete(captured.captureId);
    if (asked.kind === "drawn") {
      asked.done();
      return;
    }
    if (!captured.png) return;
    const url = URL.createObjectURL(new Blob([captured.png as Uint8Array<ArrayBuffer>], { type: "image/png" }));
    const image = new Image();
    image.src = url;
    // Decoded before it's offered, so a card that shows it draws it on its first frame.
    image.decode().then(() => {
      const previous = this.#stills.get(asked.pageId);
      if (previous && previous.askedAt > asked.at) {
        URL.revokeObjectURL(url);
        return;
      }
      if (previous) URL.revokeObjectURL(previous.url);
      this.#stills.delete(asked.pageId);
      this.#stills.set(asked.pageId, { url, width: asked.width, height: asked.height, image, askedAt: asked.at });
      for (const [pageId, still] of this.#stills) {
        if (this.#stills.size <= kept) break;
        URL.revokeObjectURL(still.url);
        this.#stills.delete(pageId);
      }
      this.#version++;
      for (const listener of this.#listeners) listener();
    }, () => URL.revokeObjectURL(url));
  }

  /** The page's latest still, or null while there is none. */
  still(pageId: string): PageStill | null {
    return this.#stills.get(pageId) ?? null;
  }

  /** Lets every still go, as the window closes. */
  clear() {
    for (const still of this.#stills.values()) URL.revokeObjectURL(still.url);
    this.#stills.clear();
    for (const asked of this.#asked.values()) if (asked.kind === "drawn") asked.done();
    this.#asked.clear();
  }
}

/** The window's stills: a window is a document of its own. */
export const pageStills = new PageStills();
