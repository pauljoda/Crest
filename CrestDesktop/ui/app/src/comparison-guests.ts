import {
  DataErased, type EngineCommand, NavigationCommitted, NavigationError, NavigationFailed, NavigationFinished, NavigationStarted, PageClosed, PageCreated,
  PageMediaActivity, PageMixedContent, PageStateChanged,
} from "@crest/contracts";
import type { EngineBindingHandler, RegisteredEngine } from "@crest/core-client";
import { SvelteSet } from "svelte/reactivity";

interface ComparisonWindow extends Window {
  chrome: { send(name: string, args: string[]): void };
  crestComparisonEvent?: (page: string, event: string, value: string, title: string, sameDocument: boolean) => void;
}

/** The isolated Mac comparison host owns a Chromium WebContents for each core page. */
export class ComparisonGuests implements EngineBindingHandler {
  readonly committed = new SvelteSet<string>();
  readonly painted = new SvelteSet<string>();
  readonly surfaces = new Map<string, string>();
  readonly #window = window as unknown as ComparisonWindow;
  readonly #escape = new Map<string, () => void>();
  readonly #erasures = new Map<string, RegisteredEngine>();
  readonly #pages = new Map<string, RegisteredEngine>();

  constructor() {
    this.#window.crestComparisonEvent = (pageId, event, value, title, sameDocument) => {
      if (event === "erased") {
        const engine = this.#erasures.get(pageId);
        this.#erasures.delete(pageId);
        void engine?.report(DataErased({ erasureId: pageId, erased: value === "true" }));
        return;
      }
      const engine = this.#pages.get(pageId);
      if (!engine) return;
      switch (event) {
        case "closed":
          this.#closed(pageId, engine);
          break;
        case "escape":
          this.#escape.get(pageId)?.();
          break;
        case "created":
          this.surfaces.set(pageId, value);
          void engine.report(PageCreated({ pageId }));
          break;
        case "painted":
          this.painted.add(pageId);
          break;
        case "unsupported":
          void engine.report(NavigationFailed({ pageId, failure: {
            error: NavigationError.unsupportedAddress, url: value, replacedDocument: false,
            domain: "CrestComparison", code: 0n,
          } }));
          break;
        case "started":
          void engine.report(NavigationStarted({ pageId, url: value, sameDocument }));
          break;
        case "committed":
          this.committed.add(pageId);
          void engine.report(NavigationCommitted({ pageId, url: value, sameDocument }));
          break;
        case "finished":
          void engine.report(PageStateChanged({ pageId, snapshot: {
            url: value, pendingUrl: null, title, isLoading: false,
            security: {
              cryptographicScheme: value.startsWith("https:"), connectionJudged: false,
              certificateError: false, engineWarns: false, mixedContent: PageMixedContent.None,
              maliciousContent: false, errorPage: false,
            },
            media: PageMediaActivity.None,
          } }));
          void engine.report(NavigationFinished({ pageId, url: value, title }));
          break;
      }
    };
  }

  holdEscape(page: string, close: () => void): () => void {
    this.#escape.set(page, close);
    this.#window.chrome.send("crestComparisonGuest", ["holdEscape", page]);
    return () => {
      this.#escape.delete(page);
      this.#window.chrome.send("crestComparisonGuest", ["releaseEscape", page]);
    };
  }

  run(command: EngineCommand, engine: RegisteredEngine): void {
    switch (command.$kind) {
      case "CreatePage":
        this.#pages.set(command.pageId, engine);
        this.#window.chrome.send("crestComparisonGuest", ["create", command.pageId, command.profileId]);
        break;
      case "EraseProfileData":
        this.#erasures.set(command.erasureId, engine);
        this.#window.chrome.send("crestComparisonGuest", ["erase", command.erasureId, command.profileId]);
        break;
      case "LoadPage":
        this.#window.chrome.send("crestComparisonGuest", ["load", command.pageId, command.url]);
        break;
      case "ClosePage":
        this.#window.chrome.send("crestComparisonGuest", ["close", command.pageId]);
        this.#closed(command.pageId, engine);
        break;
    }
  }

  #closed(pageId: string, engine: RegisteredEngine): void {
    if (!this.#pages.delete(pageId)) return;
    this.surfaces.delete(pageId);
    this.committed.delete(pageId);
    this.painted.delete(pageId);
    this.#escape.delete(pageId);
    void engine.report(PageClosed({ pageId, restoreState: null }));
  }
}
