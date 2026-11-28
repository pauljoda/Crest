import { reader } from "../reactive";

/**
 * Where a lift from the sidebar would join a window's cards, as the Mac's
 * split drop zone resolves it: the window the lift is in, and the slot among
 * its cards, in `0...cards.length`, or null while the lift aims elsewhere.
 * The sidebar's lift sets it; the window's page row draws the column the
 * card would take there. The Getting Started practice is a window of its own
 * inside the guide's, so neither row draws the other's drop.
 */
let aimed: { windowId: string | null; index: number | null } = { windowId: null, index: null };
const listeners = new Set<() => void>();

export const splitDrop = {
  set(index: number | null, windowId: string) {
    if (index === aimed.index && (index === null || windowId === aimed.windowId)) return;
    aimed = { windowId: index === null ? null : windowId, index };
    for (const listener of listeners) listener();
  },
};

/** The slot a lift in `windowId` would join its cards at, or null. */
const readAimed = reader((listener) => {
  listeners.add(listener);
  return () => listeners.delete(listener);
}, () => aimed);

export function useSplitDropIndex(windowId: string): number | null {
  const current = readAimed();
  return current.windowId === windowId ? current.index : null;
}

/**
 * BrowserSplitColumnLayout.insertionIndex: how many cards the pointer has
 * passed the middle of, among the live row's cards, or null when the pointer
 * is not over the row. The row is the window's own, or the one inside
 * `practice` for a lift from the Getting Started practice's sidebar.
 */
export function splitInsertionIndex(x: number, y: number, practice: HTMLElement | null): number | null {
  const row = practice
    ? practice.querySelector<HTMLElement>(".page-columns")
    : document.querySelector<HTMLElement>(".space-content-page.live .page-columns");
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
