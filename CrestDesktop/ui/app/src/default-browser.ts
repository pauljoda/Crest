import type { DefaultBrowserState, ShellTransport } from "@crest/core-client";

import { reader } from "./reactive";

/** BrowserDefaultBrowserStatus: what the system says about whether Crest opens links. */
export interface DefaultBrowserStatus {
  readonly title: string;
  readonly symbol: string;
  readonly tone: "quiet" | "success" | "warning";
  /** Why the system could not say, for a status it could not determine. */
  readonly message: string | null;
  /** Whether Windows' Settings can make Crest the default from here. */
  readonly offersSettings: boolean;
}

const notChecked: DefaultBrowserStatus = {
  title: "Not checked", symbol: "circle.dotted", tone: "quiet", message: null, offersSettings: true,
};
const isDefault: DefaultBrowserStatus = {
  title: "Crest", symbol: "checkmark.circle.fill", tone: "success", message: null, offersSettings: false,
};
const notDefault: DefaultBrowserStatus = {
  title: "Another browser", symbol: "circle", tone: "quiet", message: null, offersSettings: true,
};
const unavailable = (message: string, offersSettings: boolean): DefaultBrowserStatus =>
  ({ title: "Unavailable", symbol: "exclamationmark.circle", tone: "warning", message, offersSettings });

/** Windows' answer as the status the row shows. */
export function defaultBrowserStatus(state: DefaultBrowserState | null): DefaultBrowserStatus {
  switch (state) {
    case "isDefault": return isDefault;
    case "notDefault": return notDefault;
    // Windows lists a browser only once its installer registers it.
    case "unregistered": return unavailable("Install Crest to make it your default browser.", false);
    case "unknown": return unavailable("The system could not determine the default browser.", true);
    default: return unavailable("The system could not determine the default browser.", false);
  }
}

/**
 * BrowserDefaultBrowserSection's state, as Windows offers it: whether Crest
 * is the default browser, checked again on request, and, while it isn't,
 * the way to make it so. Windows lets only the person choose, in its own
 * Settings, so Open Settings… opens them on Crest's page, as
 * BrowserDefaultBrowserRequestStyle.systemSettings does, and the row checks
 * again when the person comes back to Crest.
 *
 * A view subscribes while it shows the row; the first subscriber checks.
 */
export class DefaultBrowserCheck {
  readonly #shell: ShellTransport | null;
  readonly #listeners = new Set<() => void>();
  #status = notChecked;
  #checking = true;
  #openedSettings = false;
  #generation = 0;
  #version = 0;

  constructor(shell: ShellTransport | null) {
    this.#shell = shell;
  }

  get status(): DefaultBrowserStatus {
    return this.#status;
  }

  get isChecking(): boolean {
    return this.#checking;
  }

  /** Whether Open Settings… can do anything in this window. */
  get canOpenSettings(): boolean {
    return this.#shell !== null;
  }

  /** The state's version, which grows whenever any of it changes. */
  get version(): number {
    return this.#version;
  }

  /** Calls `listener` whenever the status changes, until the returned function is called. */
  subscribe(listener: () => void): () => void {
    const first = this.#listeners.size === 0;
    this.#listeners.add(listener);
    if (first) {
      window.addEventListener("focus", this.#returned);
      void this.refresh();
    }
    return () => {
      this.#listeners.delete(listener);
      if (this.#listeners.size === 0) window.removeEventListener("focus", this.#returned);
    };
  }

  /** Asks Windows again, as Check Again does. A later check's answer wins over an earlier one's. */
  async refresh() {
    const generation = ++this.#generation;
    this.#checking = true;
    this.#changed();
    const state = this.#shell ? await this.#shell.defaultBrowser().catch(() => null) : null;
    if (generation !== this.#generation) return;
    this.#status = defaultBrowserStatus(state);
    this.#checking = false;
    this.#changed();
  }

  /** Opens Windows' Default apps on Crest's page, where the person makes the choice. */
  openSettings() {
    const shell = this.#shell;
    if (!shell) return;
    this.#openedSettings = true;
    void shell.openDefaultApps().then((opened) => {
      if (!opened) this.#openedSettings = false;
    });
  }

  // The choice is made in Windows' Settings, another app; once the person
  // comes back from it, the row says what they chose.
  readonly #returned = () => {
    if (!this.#openedSettings) return;
    this.#openedSettings = false;
    void this.refresh();
  };

  #changed() {
    this.#version += 1;
    for (const listener of this.#listeners) listener();
  }
}

const readers = new WeakMap<DefaultBrowserCheck, () => number>();

/**
 * `check`, followed by the expression that reads it: call it inside the
 * `$derived` or template expression that reads from it. The first such
 * expression starts the check, and the last one to stop ends its watch for
 * the person's return from Settings.
 */
export function useDefaultBrowserCheck(check: DefaultBrowserCheck): DefaultBrowserCheck {
  let read = readers.get(check);
  if (!read) {
    read = reader((listener) => check.subscribe(listener), () => check.version);
    readers.set(check, read);
  }
  read();
  return check;
}
