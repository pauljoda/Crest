import { previewFolders, previewTabs } from "../appearance.svelte";

/** BrowserTabPreviewState's timing, in milliseconds. */
const timing = { rest: 500, move: 120, aim: 350, leave: 150 };

/** The tab a card shows, and the row it stands beside. */
interface Shown {
  readonly kind: "tab" | "folder";
  readonly id: string;
  readonly row: DOMRect;
}

type Point = { readonly x: number; readonly y: number };

/**
 * The Mac's BrowserTabPreviewState: which tab's card shows, from where the
 * pointer rests. A row rested on for half a second shows its tab's card;
 * while a card shows, another row takes it after 120 ms, or 350 ms while the
 * pointer crosses rows on its way into the card; the card goes 150 ms after
 * the pointer leaves both the row and the card. A card put away by a key, a
 * press or a scroll stays away until the pointer enters a row again.
 */
export class PreviewState {
  held = false;
  enabled = false;
  card: HTMLElement | undefined;
  #shown = $state.raw<Shown | null>(null);
  #timer = 0;
  #resting: string | null = null;
  #onCard = false;
  /** Whether the pointer has gone onto the page since it last rested on a row or the card. */
  #onPage = false;
  /** Where the pointer left the shown row, for telling a crossing on the way into the card. */
  #leftAt: Point | null = null;

  get shown(): Shown | null {
    return this.#shown;
  }

  /**
   * The pointer moved onto the page beside the sidebar, which tells the
   * interface nothing of the pointer itself: it left the row it rested on.
   */
  pointerOnPage(pointer: Point) {
    // The first move says it; the moves after it only wait out the leave.
    if (this.#onPage) return;
    this.#onPage = true;
    if (this.#resting) this.leave(this.#resting, pointer);
    this.#onCard = false;
    this.#scheduleLeave();
  }

  /** The pointer came to rest on a tab's row. */
  rest(kind: Shown["kind"], id: string, row: HTMLElement, pointer: Point) {
    if (!this.enabled || this.held || !(kind === "folder" ? previewFolders.current : previewTabs.current)) return;
    if (this.#resting === id) return;
    this.#resting = id;
    this.#onPage = false;
    clearTimeout(this.#timer);
    const delay = !this.#shown ? timing.rest : this.#aimsAtCard(pointer) ? timing.aim : timing.move;
    this.#timer = window.setTimeout(() => {
      if (this.#resting !== id || !row.isConnected) return;
      this.#show({ kind, id, row: row.getBoundingClientRect() });
    }, delay);
  }

  /** The pointer left a tab's row. */
  leave(id: string, pointer: Point) {
    if (this.#resting === id) this.#resting = null;
    if (this.#shown?.id === id) this.#leftAt = pointer;
    this.#scheduleLeave();
  }

  enterCard() {
    this.#onCard = true;
    this.#onPage = false;
    clearTimeout(this.#timer);
  }

  leaveCard() {
    this.#onCard = false;
    this.#scheduleLeave();
  }

  /** Puts the card away until the pointer enters a row again. */
  dismiss() {
    if (!this.#shown && !this.#resting) return;
    this.#resting = null;
    clearTimeout(this.#timer);
    this.#show(null);
  }

  #scheduleLeave() {
    clearTimeout(this.#timer);
    this.#timer = window.setTimeout(() => {
      if (!this.held && !this.#onCard && !this.#resting) this.#show(null);
    }, timing.leave);
  }

  #show(next: Shown | null) {
    if (next === null) {
      this.#onCard = false;
      this.#onPage = false;
      this.held = false;
    }
    this.#shown = next;
  }

  /** Whether the pointer is inside the triangle from where it left the row to the card's near edge. */
  #aimsAtCard(pointer: Point): boolean {
    const card = this.card?.getBoundingClientRect();
    const from = this.#leftAt;
    if (!card || !from) return false;
    const a = from;
    const edge = from.x > card.right ? card.right : card.left;
    const b = { x: edge, y: card.top };
    const c = { x: edge, y: card.bottom };
    const side = (p: Point, q: Point, r: Point) => (p.x - r.x) * (q.y - r.y) - (q.x - r.x) * (p.y - r.y);
    const d1 = side(pointer, a, b);
    const d2 = side(pointer, b, c);
    const d3 = side(pointer, c, a);
    return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0));
  }
}

export const tabPreview = new PreviewState();

/** The handlers a tab row gives the pointer, which tell the card where it rests. */
export function previewHandlers(id: string, kind: Shown["kind"] = "tab", state = tabPreview) {
  return {
    onpointerenter: (event: PointerEvent & { currentTarget: EventTarget & HTMLElement }) =>
      state.rest(kind, id, event.currentTarget, { x: event.clientX, y: event.clientY }),
    onpointerleave: (event: PointerEvent) => state.leave(id, { x: event.clientX, y: event.clientY }),
  };
}
