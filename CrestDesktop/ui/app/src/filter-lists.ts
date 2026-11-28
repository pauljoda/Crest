import {
  DueFilterDownloads,
  type FilterDownload,
  FilterDownloadFailed,
  FilterDownloadFetched,
  FilterDownloadNotModified,
  FilterDownloadTooLarge,
  type Intent,
} from "@crest/contracts";
import type { CrestCore, ShellTransport } from "@crest/core-client";

/** How often the updater asks the core what is due while Crest runs. */
const interval = 60 * 60 * 1000;
/**
 * How long one list's download may take before it counts as failed, so a
 * stalled one can't hold back the lists due after it. The Mac's request gives
 * up after a minute without data; the engine's fetch sets no bound of its own.
 */
const downloadTimeout = 5 * 60 * 1000;

/**
 * The Mac's BrowserFilterListUpdater: downloads the filter lists the core
 * says are due, the catalog's and the ones the person added, and hands each
 * one back to the core, which keeps it, converts it and decides when it is
 * due again. The updater only fetches, with the validators the core gives,
 * so a list that has not changed costs a conditional request. It asks when
 * the window starts, every hour while it runs, and whenever the lists or
 * Super Copy change, so a list the person adds or turns on arrives at once.
 * The engine fetches without cookies or stored credentials, follows
 * redirects only to https addresses, and stops a download that grows past
 * what the core keeps. Each window runs one; the core hands each download to
 * only one of them.
 */
export class FilterListUpdater {
  readonly #core: CrestCore;
  readonly #shell: ShellTransport;
  #checking: Promise<void> | null = null;
  /** Whether a check came in while one ran. */
  #checksAgain = false;
  #stop: (() => void) | null = null;

  constructor(core: CrestCore, shell: ShellTransport) {
    this.#core = core;
    this.#shell = shell;
  }

  /** Checks now, then every hour and whenever the lists or Super Copy change, until `stop`. */
  start() {
    if (this.#stop) return;
    const timer = setInterval(() => void this.check(), interval);
    let lists = this.#core.state.filterLists;
    let cleans = this.#core.state.links?.cleansCopiedLinks;
    // The core answers only what is due, so a change a download made asks for nothing more.
    const unsubscribe = this.#core.state.subscribe(() => {
      const state = this.#core.state;
      if (state.filterLists === lists && state.links?.cleansCopiedLinks === cleans) return;
      lists = state.filterLists;
      cleans = state.links?.cleansCopiedLinks;
      void this.check();
    });
    this.#stop = () => {
      clearInterval(timer);
      unsubscribe();
    };
    void this.check();
  }

  stop() {
    this.#stop?.();
    this.#stop = null;
  }

  /** Downloads each list due now, one at a time, and asks again when a check came in meanwhile. */
  check(): Promise<void> {
    if (this.#checking) {
      this.#checksAgain = true;
      return this.#checking;
    }
    this.#checking = (async () => {
      try {
        do {
          this.#checksAgain = false;
          const due = await this.#core.query(DueFilterDownloads()).catch(() => []);
          for (const fetch of due) await this.#core.send(await this.#outcome(fetch)).catch(() => {});
        } while (this.#checksAgain);
      } finally {
        this.#checking = null;
      }
    })();
    return this.#checking;
  }

  /** What the download of `fetch` brought, as the intent that tells the core. */
  async #outcome(fetch: FilterDownload): Promise<Intent> {
    try {
      const fetched = await within(downloadTimeout, this.#shell.fetchText(fetch.url, "filterList", fetch.entityTag, fetch.lastModified));
      if (fetched.tooLarge) return FilterDownloadTooLarge({ id: fetch.id });
      if (fetched.status === 304) return FilterDownloadNotModified({ id: fetch.id });
      if (fetched.status !== 200 || fetched.text === null) return FilterDownloadFailed({ id: fetch.id });
      return FilterDownloadFetched({ id: fetch.id, text: fetched.text, entityTag: fetched.entityTag, lastModified: fetched.lastModified });
    } catch {
      return FilterDownloadFailed({ id: fetch.id });
    }
  }
}

/** `promise`, or a failure once `milliseconds` pass without it settling. */
function within<T>(milliseconds: number, promise: Promise<T>): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const expired = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`No answer within ${milliseconds} ms`)), milliseconds);
  });
  return Promise.race([promise, expired]).finally(() => clearTimeout(timer));
}

/** This window's updater, once its session has started one. */
export let filterListUpdater: FilterListUpdater | null = null;

export function startFilterListUpdates(core: CrestCore, shell: ShellTransport) {
  filterListUpdater?.stop();
  filterListUpdater = new FilterListUpdater(core, shell);
  filterListUpdater.start();
}
