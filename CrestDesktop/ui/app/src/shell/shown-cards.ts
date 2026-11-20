import type { WindowState } from "@crest/contracts";

/**
 * The cards a window shows for a Space, as the core keeps them in its window
 * state (`ShownCards`): a Split View's members side by side, or the shown tab
 * alone; and how the columns share the width (`SplitColumnShares`).
 */
export interface SpaceCards {
  /** The tabs the cards show, in column order. */
  readonly tabIds: readonly string[];
  /** The split the cards are, or null for a lone tab. */
  readonly groupId: string | null;
  /** Each column's share of the width, summing to one. */
  readonly shares: readonly number[];
}

export function spaceCards(window: WindowState | undefined, spaceId: string, shownTabId: string | null): SpaceCards {
  const cards = window?.cards.find((entry) => entry.spaceId === spaceId);
  const tabIds = cards && cards.tabIds.length > 0 ? cards.tabIds : shownTabId ? [shownTabId] : [];
  const groupId = cards?.splitGroupId ?? null;
  const stored = groupId ? window?.splitColumnShares.find((entry) => entry.groupId === groupId)?.shares : undefined;
  return { tabIds, groupId, shares: seedShares(stored, tabIds.length) };
}

/** BrowserSplitLayoutMetrics and BrowserSplitCardResizeHandleMetrics. */
export const splitMetrics = Object.freeze({
  /** The space between cards, the page frame's own inset. */
  gap: 8,
  /** No card is narrower; a row that cannot seat every card at it clips. */
  minimumCardWidth: 240,
  /** A divider's target: the gap and 4 points over each card beside it. */
  handleHitWidth: 16,
  /** How far one accessibility step moves a divider. */
  keyboardStep: 24,
});

/** The shares a split starts with: its stored ones while they fit its members, equal columns otherwise. */
function seedShares(stored: readonly number[] | undefined, count: number): number[] {
  if (count === 0) return [];
  return stored && stored.length === count ? normalizedShares(stored) : equalShares(count);
}

function equalShares(count: number): number[] {
  return Array.from({ length: count }, () => 1 / count);
}

/** Shares summing to one; a list with anything that cannot be a share is equal columns in full. */
export function normalizedShares(shares: readonly number[]): number[] {
  if (shares.length === 0) return [];
  if (!shares.every((share) => Number.isFinite(share) && share > 0)) return equalShares(shares.length);
  const total = shares.reduce((sum, share) => sum + share, 0);
  return Number.isFinite(total) && total > 0 ? shares.map((share) => share / total) : equalShares(shares.length);
}

/**
 * BrowserSplitColumnLayout.fractionsAfterResize: the shares a divider drag
 * lands on, `delta` being the pointer's travel since the drag began. Only
 * the pair around the divider moves, and their boundary stops as either
 * reaches the minimum width.
 */
export function sharesAfterResize(shares: readonly number[], divider: number, delta: number, rowWidth: number): number[] {
  const result = normalizedShares(shares);
  if (result.length < 2 || divider < 0 || divider >= result.length - 1) return result;
  const available = rowWidth - splitMetrics.gap * (result.length - 1);
  if (available <= 0) return result;
  const floor = splitMetrics.minimumCardWidth;
  const pair = available * (result[divider] + result[divider + 1]);
  if (pair < floor * 2) return result;
  const leading = Math.min(Math.max(available * result[divider] + delta, floor), pair - floor);
  result[divider] = leading / available;
  result[divider + 1] = (pair - leading) / available;
  return result;
}

/**
 * BrowserSplitColumnLayout.fractionsInserting: the shares after a card joins
 * at `index`, which takes an equal share of the wider row while the others
 * give it up in proportion, so a resized pair stays as lopsided as it was.
 */
export function sharesInserting(index: number, shares: readonly number[]): number[] {
  if (shares.length === 0) return [1];
  const newcomer = 1 / (shares.length + 1);
  const result = normalizedShares(shares).map((share) => share * (1 - newcomer));
  result.splice(Math.min(Math.max(index, 0), result.length), 0, newcomer);
  return result;
}

export function sameMembers(members: readonly string[], other: readonly string[]): boolean {
  return members.length === other.length && members.every((member, index) => member === other[index]);
}

/** Whether a drag moved the shares enough to keep: BrowserSplitWidthTransaction's half a thousandth. */
export function sharesDiffer(shares: readonly number[], other: readonly number[]): boolean {
  return shares.length !== other.length || shares.some((share, index) => Math.abs(share - other[index]) >= 0.0005);
}

/**
 * BrowserSplitCardIdentities: which card each member is drawn in, and whether
 * the last change to the members settles with the row's motion. A card keeps
 * its member for the life of the row, so a tab joining, leaving or moving
 * leaves the other cards where they are; a lone card is the exception, and
 * another tab shown alone takes it over, as a tab switch outside a split
 * always has, landing at once.
 */
export class CardIdentities {
  #cards = new Map<string, string>();
  #last: readonly string[] = [];
  #settles = true;

  /** Whether the last change to the members settles with the row's motion. */
  get settles(): boolean {
    return this.#settles;
  }

  cards(members: readonly string[]): ReadonlyMap<string, string> {
    if (sameMembers(members, this.#last)) return this.#cards;
    const next = new Map<string, string>();
    for (const member of members) {
      const card = this.#cards.get(member);
      if (card) next.set(member, card);
    }
    if (members.length === 1 && this.#last.length === 1 && next.size === 0) {
      const card = this.#cards.values().next().value;
      if (card) next.set(members[0], card);
    }
    const taken = new Set(next.values());
    for (const member of members) {
      if (next.has(member)) continue;
      // A tab whose own identity a lone card already wears takes a new one.
      const card = taken.has(member) ? crypto.randomUUID() : member;
      next.set(member, card);
      taken.add(card);
    }
    const old = this.#last;
    this.#settles = !(old.length === 1 || members.length === 1) || old.some((member) => members.includes(member));
    this.#cards = next;
    this.#last = [...members];
    return next;
  }
}
