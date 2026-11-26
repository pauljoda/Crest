/**
 * A transient message over the window's page, as the Mac's BrowserNotice is:
 * it asks nothing of the person, and reports a copy, a refusal or how to run
 * a command. A notice with a `key` can be put away early by that key once
 * what it reports no longer holds.
 */
export interface WindowNotice {
  readonly message: string;
  readonly symbol: string;
  readonly key?: string;
  /** What assistive technology reads where the message alone says too little, such as "Page zoom 125%". */
  readonly accessibilityLabel?: string;
}

type NoticeEvent = { readonly shows: WindowNotice } | { readonly dismisses: string };

const listeners = new Set<(event: NoticeEvent) => void>();

/** The notices this window's interface posts; the window's notice layer shows them. */
export const notices = Object.freeze({
  /** Shows `notice`, replacing any notice still showing. */
  post(notice: WindowNotice) {
    for (const listener of listeners) listener({ shows: notice });
  },
  /** Puts away the notice posted with `key`, if it is the one showing. */
  dismiss(key: string) {
    for (const listener of listeners) listener({ dismisses: key });
  },
  subscribe(listener: (event: NoticeEvent) => void): () => void {
    listeners.add(listener);
    return () => listeners.delete(listener);
  },
});

/** A page's address went to the clipboard. */
export const urlCopiedNotice: WindowNotice = { message: "URL Copied", symbol: "checkmark.circle.fill" };

/** Text went to the clipboard. */
export const copiedNotice: WindowNotice = { message: "Copied", symbol: "checkmark.circle.fill" };

/** An action that could not run, with `reason` saying why. */
export const failureNotice = (reason: string): WindowNotice => ({ message: reason, symbol: "exclamationmark.triangle.fill" });

/** How long a notice stays: long enough to read, as the Mac's do. */
export function noticeDuration(message: string): number {
  return Math.min(Math.max(1400, message.length * 60), 6000);
}
