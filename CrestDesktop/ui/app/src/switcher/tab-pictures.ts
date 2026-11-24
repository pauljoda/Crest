import { CapturePage, type PageCaptured } from "@crest/contracts";
import type { CrestCore } from "@crest/core-client";
import { reader } from "../reactive";

/** A page the window shows that a picture may be taken of. */
export interface PicturedPage {
  readonly pageId: string;
  readonly tabId: string;
  readonly address: string;
}

interface Picture {
  readonly url: string;
  readonly address: string;
  readonly at: number;
}

/**
 * The Mac's BrowserTabPictures: pictures of the pages a window has shown,
 * for the recent-tab switcher, kept in memory for the window only. A page is
 * pictured by its engine at most every 10 seconds, at the same address at
 * most every 30 unless the switcher asks for it fresh, and the window keeps
 * the latest hundred.
 */
export class TabPictures {
  #pictures = new Map<string, Picture>();
  #asked = new Map<string, { readonly tabId: string; readonly address: string }>();
  #listeners = new Set<() => void>();
  #version = 0;

  /** Asks the page's engine for a picture of it, unless one was taken lately. */
  capture(core: CrestCore, page: PicturedPage, fresh = false) {
    const last = this.#pictures.get(page.tabId);
    const age = last ? performance.now() - last.at : Infinity;
    if (!fresh && (age < 10_000 || (last?.address === page.address && age < 30_000))) return;
    if ([...this.#asked.values()].some((asked) => asked.tabId === page.tabId)) return;
    const captureId = crypto.randomUUID();
    this.#asked.set(captureId, { tabId: page.tabId, address: page.address });
    void core.request(CapturePage({ pageId: page.pageId, captureId, area: null, width: 320 }))
      .catch(() => this.#asked.delete(captureId));
  }

  /** Keeps the picture an engine took for a capture this window asked for. */
  received(captured: PageCaptured) {
    const asked = this.#asked.get(captured.captureId);
    if (!asked) return;
    this.#asked.delete(captured.captureId);
    if (!captured.png) return;
    const previous = this.#pictures.get(asked.tabId);
    if (previous) URL.revokeObjectURL(previous.url);
    this.#pictures.delete(asked.tabId);
    const url = URL.createObjectURL(new Blob([captured.png as Uint8Array<ArrayBuffer>], { type: "image/png" }));
    this.#pictures.set(asked.tabId, { url, address: asked.address, at: performance.now() });
    for (const [tabId, picture] of this.#pictures) {
      if (this.#pictures.size <= 100) break;
      URL.revokeObjectURL(picture.url);
      this.#pictures.delete(tabId);
    }
    this.#version++;
    for (const listener of this.#listeners) listener();
  }

  /** The latest picture of the tab's page, or null while there is none. */
  picture(tabId: string): string | null {
    return this.#pictures.get(tabId)?.url ?? null;
  }

  subscribe(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  get version(): number {
    return this.#version;
  }

  /** Lets every picture go, as the window closes. */
  clear() {
    for (const picture of this.#pictures.values()) URL.revokeObjectURL(picture.url);
    this.#pictures.clear();
    this.#asked.clear();
  }
}

/** Follows the pictures a window keeps. */
const pictureReaders = new WeakMap<TabPictures, () => number>();

/** The pictures' version, followed by the expression that reads it. */
export function useTabPictures(pictures: TabPictures): number {
  let read = pictureReaders.get(pictures);
  if (!read) {
    read = reader((listener) => pictures.subscribe(listener), () => pictures.version);
    pictureReaders.set(pictures, read);
  }
  return read();
}
