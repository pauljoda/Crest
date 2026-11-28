import type { AddressCompletion } from "@crest/contracts";

/**
 * Tracks the field's editing without putting the proposed suffix into the
 * query, as the Mac's BrowserURLCompletionEditingState does. A completion
 * shows only while the caret rests at the end of what was typed, nothing is
 * being composed, and the last edit added text rather than deleting it.
 */
export class CompletionEditing {
  #text = "";
  #selectionStart = 0;
  #selectionEnd = 0;
  #composing = false;
  #suppressed = true;

  update(text: string, selectionStart: number, selectionEnd: number, composing: boolean) {
    if (text !== this.#text) this.#suppressed = text.length < this.#text.length;
    this.#text = text;
    this.#selectionStart = selectionStart;
    this.#selectionEnd = selectionEnd;
    this.#composing = composing;
  }

  reject() {
    this.#suppressed = true;
  }

  get isComposing(): boolean {
    return this.#composing;
  }

  /** The caret rests at the end of the text with nothing being composed. */
  get isAtEnd(): boolean {
    return !this.#composing && this.#selectionStart === this.#text.length && this.#selectionEnd === this.#text.length;
  }

  canPropose(query: string): boolean {
    return !this.#suppressed && !this.#composing && this.#text === query &&
      this.#selectionStart === query.length && this.#selectionEnd === query.length;
  }
}

/** What accepting `completion` types: its suffix when it only adds to what was typed, else the whole accepted address. */
export function completedText(completion: AddressCompletion): string {
  return completion.typed + completion.suffix;
}

/**
 * `completion` for `text`: itself when `text` is what it completes, the rest
 * of its suffix when `text` types further into that suffix, or null when
 * `text` leaves it or types all of it. The field keeps showing it while the
 * core ranks the new text, so a keystroke that still matches never blanks
 * it. The scheme and host match in any case, the path only exactly, as the
 * core compares them.
 */
export function continued(completion: AddressCompletion, text: string): AddressCompletion | null {
  const typed = completion.typed;
  if (text === typed) return completion;
  if (!text.startsWith(typed)) return null;
  const completed = completedText(completion);
  if (text.length >= completed.length) return null;
  const pathStart = pathStartOf(completed);
  for (let position = typed.length; position < text.length; position++) {
    const unit = text[position];
    const expected = completed[position];
    const matches = position < pathStart ? sameIgnoringCase(unit, expected) : unit === expected;
    if (!matches) return null;
  }
  return { typed: text, suffix: completed.slice(text.length), accepted: completion.accepted };
}

/** Where the path begins in `address`: its first `/` after an `http://` or `https://` it starts with, or its end. */
function pathStartOf(address: string): number {
  const scheme = ["https://", "http://"].find((prefix) => address.slice(0, prefix.length).toLowerCase() === prefix);
  const slash = address.indexOf("/", scheme?.length ?? 0);
  return slash < 0 ? address.length : slash;
}

function sameIgnoringCase(unit: string, other: string): boolean {
  if (unit === other) return true;
  const isSurrogate = (value: string) => /[\uD800-\uDFFF]/.test(value);
  if (isSurrogate(unit) || isSurrogate(other)) return false;
  return unit.toLowerCase() === other.toLowerCase();
}
