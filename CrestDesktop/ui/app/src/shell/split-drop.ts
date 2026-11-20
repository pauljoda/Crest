import { useSyncExternalStore } from "react";

/**
 * Where a lift from the sidebar would join the window's cards, as the Mac's
 * split drop zone resolves it: the slot among the cards, in
 * `0...cards.length`, or null while the lift aims elsewhere. The sidebar's
 * lift sets it; the page row draws the column the card would take there.
 */
let index: number | null = null;
const listeners = new Set<() => void>();

export const splitDrop = {
  set(next: number | null) {
    if (next === index) return;
    index = next;
    for (const listener of listeners) listener();
  },
  get index(): number | null {
    return index;
  },
};

/** The slot a lift would join the cards at, or null. */
export function useSplitDropIndex(): number | null {
  return useSyncExternalStore((listener) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  }, () => index);
}

/**
 * BrowserSplitColumnLayout.insertionIndex: how many cards the pointer has
 * passed the middle of, among the live row's cards, or null when the pointer
 * is not over the row.
 */
export function splitInsertionIndex(x: number, y: number): number | null {
  const row = document.querySelector<HTMLElement>(".space-content-page.live .page-columns");
  if (!row) return null;
  const bounds = row.getBoundingClientRect();
  if (x < bounds.left || x > bounds.right || y < bounds.top || y > bounds.bottom) return null;
  // A sidebar floating over the cards is the sidebar's.
  if (document.elementsFromPoint(x, y).some((element) => element.closest(".sidebar"))) return null;
  const cards = [...row.querySelectorAll<HTMLElement>(":scope > .page-column:not(.page-placeholder)")]
    .map((column) => column.getBoundingClientRect())
    .filter((rect) => rect.width > 0)
    .sort((left, right) => left.left - right.left);
  let passed = 0;
  for (const card of cards) {
    if (x <= card.left + card.width / 2) break;
    passed++;
  }
  return passed;
}
