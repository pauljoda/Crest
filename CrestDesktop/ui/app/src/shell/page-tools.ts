import { FindInPage, type FindFinished, ZoomPage } from "@crest/contracts";
import type { CrestCore } from "@crest/core-client";
import { reader } from "../reactive";

/** What a search has turned up so far, as the Mac's BrowserFindMatchState names it. */
export type FindMatchState = "idle" | "searching" | "found" | "notFound";

/** Which match a search selected, counted from 1, out of how many the page holds. */
export interface FindMatches {
  readonly active: number;
  readonly total: number;
}

/**
 * One page's find, as the Mac's BrowserFindSession keeps it: whether its bar
 * shows, what it searched for and found, and how many times find was asked
 * for, each ask being a request for the bar's field.
 */
export interface FindSession {
  readonly presented: boolean;
  readonly query: string;
  readonly matchState: FindMatchState;
  /** Nil when nothing was found or the engine cannot count. */
  readonly matches: FindMatches | null;
  readonly focusRequest: number;
  /** Whether the bar takes its field when it appears; finding again leaves the keys with the page. */
  readonly focusesQueryField: boolean;
  /** The last query searched for, which finding again reuses once the bar has closed. */
  readonly lastQuery: string;
}

const closed: FindSession = {
  presented: false, query: "", matchState: "idle", matches: null, focusRequest: 0, focusesQueryField: true, lastQuery: "",
};

/** The zoom levels a page steps through, as the Mac's pageZoomLevels. */
const zoomLevels = [0.5, 0.67, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3];
const zoomTolerance = 0.001;
/** The zoom a page opens at and Actual Size returns to, until Windows has the Mac's default zoom setting. */
const defaultZoom = 1;

/**
 * The page work this window keeps for each page it shows, as the Mac's
 * BrowserPage keeps it beside the page: find in page and zoom. The engine
 * does the searching and zooming (`FindInPage`, `ZoomPage`) and reports what
 * a search found (`FindFinished`).
 */
class PageTools {
  #finds = new Map<string, FindSession>();
  #zooms = new Map<string, number>();
  // Each page's zoom steps run one after another, each from the zoom the one before reached.
  #zoomSteps = new Map<string, Promise<number | null>>();
  #listeners = new Set<() => void>();
  version = 0;

  subscribe = (listener: () => void) => {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  };

  find(pageId: string): FindSession {
    return this.#finds.get(pageId) ?? closed;
  }

  /** Whether there is a query to find again: the bar's own while it shows, or the last one searched for. */
  canFindAgain(pageId: string): boolean {
    const session = this.find(pageId);
    return (session.presented ? session.query : session.lastQuery) !== "";
  }

  /** Shows the bar and asks for its field, on a page that has loaded something. */
  present(pageId: string, hasLoadedPage: boolean) {
    if (!hasLoadedPage) return;
    const session = this.find(pageId);
    this.#set(pageId, { ...session, presented: true, focusesQueryField: true, focusRequest: session.focusRequest + 1 });
  }

  /** Searches for `query` and moves to the match `backwards` asks for; an empty query clears the search. */
  search(core: CrestCore, pageId: string, query: string, backwards = false) {
    const session = this.find(pageId);
    const lastQuery = query === "" ? session.lastQuery : query;
    if (query === "") {
      this.#set(pageId, { ...session, query, lastQuery, matchState: "idle", matches: null });
      this.#clear(core, pageId);
      return;
    }
    this.#set(pageId, { ...session, query, lastQuery, matchState: "searching" });
    void core.request(FindInPage({ pageId, query, backwards, caseSensitive: false })).then(
      (searching) => !searching && this.#settle(pageId, query, "notFound", null),
      () => this.#settle(pageId, query, "notFound", null),
    );
  }

  /** Moves to the next or previous match of the query there is to find again, bringing a closed bar back without its field's focus. */
  findAgain(core: CrestCore, pageId: string, backwards: boolean, hasLoadedPage: boolean) {
    const session = this.find(pageId);
    const query = session.presented ? session.query : session.lastQuery;
    if (!hasLoadedPage || query === "") return;
    if (!session.presented) this.#set(pageId, { ...session, presented: true, focusesQueryField: false });
    this.search(core, pageId, query, backwards);
  }

  /** Closes the bar and clears the page's highlight. */
  dismiss(core: CrestCore, pageId: string) {
    const session = this.find(pageId);
    this.#set(pageId, { ...session, presented: false, query: "", matchState: "idle", matches: null });
    this.#clear(core, pageId);
  }

  /** The engine's answer to the search the page last asked for. */
  finished(report: FindFinished) {
    const session = this.#finds.get(report.pageId);
    if (!session || session.matchState !== "searching") return;
    const total = report.matches ?? 0;
    if (total <= 0) return this.#settle(report.pageId, session.query, "notFound", null);
    const counted = report.activeMatch >= 1 && report.activeMatch <= total ? { active: report.activeMatch, total } : null;
    this.#settle(report.pageId, session.query, "found", counted);
  }

  /** The page's zoom. */
  zoom(pageId: string): number {
    return this.#zooms.get(pageId) ?? defaultZoom;
  }

  /**
   * Steps the page's zoom a level in or out, or back to its default, as the
   * Mac's page does; answers the zoom it reached, or null where it did not
   * change.
   */
  setZoom(core: CrestCore, pageId: string, step: "in" | "out" | "reset"): Promise<number | null> {
    const before = this.#zoomSteps.get(pageId) ?? Promise.resolve(null);
    const reached = before.then(() => this.#stepZoom(core, pageId, step)).catch(() => null);
    this.#zoomSteps.set(pageId, reached);
    void reached.then(() => {
      if (this.#zoomSteps.get(pageId) === reached) this.#zoomSteps.delete(pageId);
    });
    return reached;
  }

  async #stepZoom(core: CrestCore, pageId: string, step: "in" | "out" | "reset"): Promise<number | null> {
    const current = this.zoom(pageId);
    const next = step === "reset" ? defaultZoom
      : step === "in" ? zoomLevels.find((level) => level > current + zoomTolerance) ?? Math.max(current, zoomLevels.at(-1)!)
        : zoomLevels.findLast((level) => level < current - zoomTolerance) ?? Math.min(current, zoomLevels[0]);
    if (Math.abs(next - current) <= zoomTolerance) return null;
    if (!(await core.request(ZoomPage({ pageId, factor: next })).catch(() => false))) return null;
    this.#zooms.set(pageId, next);
    this.#changed();
    return next;
  }

  #settle(pageId: string, query: string, matchState: FindMatchState, matches: FindMatches | null) {
    const session = this.find(pageId);
    // A later search, or a closed bar, outranks this answer.
    if (session.query !== query || session.matchState !== "searching") return;
    this.#set(pageId, { ...session, matchState, matches });
  }

  #clear(core: CrestCore, pageId: string) {
    void core.request(FindInPage({ pageId, query: "", backwards: false, caseSensitive: false })).catch(() => undefined);
  }

  #set(pageId: string, session: FindSession) {
    this.#finds.set(pageId, session);
    this.#changed();
  }

  #changed() {
    this.version++;
    for (const listener of this.#listeners) listener();
  }
}

/** This window's page work. Each window is its own document, so it keeps its own. */
export const pageTools = new PageTools();

/** Redraws with the window's page work. */
const readPageTools = reader(pageTools.subscribe, () => pageTools.version);

/**
 * The window's page tools, followed by the expression that reads them: call
 * it inside the `$derived` or template expression that reads from it.
 */
export function usePageTools(): PageTools {
  readPageTools();
  return pageTools;
}

/** A zoom as the person reads it, such as "125%". */
export function zoomPercentage(zoom: number): string {
  return `${Math.round(zoom * 100)}%`;
}
