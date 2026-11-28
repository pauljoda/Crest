import {
  type EngineCommand,
  type EngineEvent,
  NavigationCommitted,
  NavigationFinished,
  NavigationStarted,
  PageClosed,
  PageCreated,
  PageMediaActivity,
  PageMixedContent,
  PageStateChanged,
} from "@crest/contracts";
import type { EngineBindingHandler, RegisteredEngine } from "@crest/core-client";

/** One page the development engine holds: a frame the page card shows. */
export interface DevPage {
  readonly id: string;
  readonly url: string | null;
}

/**
 * The engine the interface runs against in an ordinary browser: each page is
 * a frame. It answers the core's commands as an engine binding does and
 * reports what a frame can tell it. Crest's Chromium replaces it in the
 * product; it exists so the interface is built against the real core and
 * engine contract from the first day.
 */
export class DevEngine implements EngineBindingHandler {
  pages = new Map<string, DevPage>();
  #listeners = new Set<() => void>();
  /** Each page's latest load, so an older load stops reporting once a newer one starts. */
  #loads = new Map<string, number>();
  version = 0;

  run(command: EngineCommand, engine: RegisteredEngine): void {
    switch (command.$kind) {
      case "CreatePage":
        this.#set({ id: command.pageId, url: null });
        void engine.report(PageCreated({ pageId: command.pageId }));
        break;
      case "LoadPage": {
        const load = (this.#loads.get(command.pageId) ?? 0) + 1;
        this.#loads.set(command.pageId, load);
        this.#set({ id: command.pageId, url: command.url });
        void this.#reportLoad(engine, command.pageId, command.url, load);
        break;
      }
      case "ClosePage":
        this.pages.delete(command.pageId);
        this.#loads.delete(command.pageId);
        this.#changed();
        void engine.report(PageClosed({ pageId: command.pageId, restoreState: null }));
        break;
      default:
        console.debug("Development engine ignores", command.$kind, command);
    }
  }

  subscribe(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  async #reportLoad(engine: RegisteredEngine, pageId: string, url: string, load: number) {
    const secure = url.startsWith("https:");
    const title = (() => {
      try {
        return new URL(url).hostname || url;
      } catch {
        return url;
      }
    })();
    // A newer load of the page, or its closing, supersedes this one: it reports nothing further.
    const report = async (event: EngineEvent) => {
      if (this.#loads.get(pageId) === load) await engine.report(event);
    };
    await report(NavigationStarted({ pageId, url, sameDocument: false }));
    await report(NavigationCommitted({ pageId, url, sameDocument: false }));
    await report(
      PageStateChanged({
        pageId,
        snapshot: {
          url,
          pendingUrl: null,
          title,
          isLoading: false,
          security: {
            cryptographicScheme: secure,
            connectionJudged: secure,
            certificateError: false,
            engineWarns: false,
            mixedContent: PageMixedContent.None,
            maliciousContent: false,
            errorPage: false,
          },
          media: PageMediaActivity.None,
        },
      }),
    );
    await report(NavigationFinished({ pageId, url, title }));
  }

  #set(page: DevPage) {
    this.pages.set(page.id, page);
    this.#changed();
  }

  #changed() {
    this.version++;
    for (const listener of this.#listeners) listener();
  }
}
