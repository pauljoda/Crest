import type { TransitionConfig } from "svelte/transition";

import { presence, type PresenceOptions, reducesMotion, timed, type Timing } from "../motion";

/**
 * Motion's `layout` and `popLayout` for the page row (PageColumns), whose
 * changes move its cards, its drop column's card and its dividers. The row
 * measures them before Svelte draws a change and moves each from where it
 * stood to where it stands on the compositor, as Motion measured before
 * React drew; and a column or divider that goes lifts out of the row where
 * it stood before the change, while what stays takes its place at once.
 */

/** How a page card moves into a new place, as Motion's `layout` and `transition` on the card said. */
export interface CardLayout {
  /** The spring or curve the card moves on now, or null where it takes the change at once. */
  timing(): Timing | null;
  /** The card began to move. */
  started(): void;
  /** The card came to rest. */
  finished(): void;
}

/** Each page card's layout, kept by the card (PageCard) for as long as it shows. */
export const cardLayouts = new WeakMap<Element, CardLayout>();

/** What a row moves: its cards, the drop column's card, and its dividers, which only change place. */
const movers = ":scope > .page-column > .page-card, :scope > .page-placeholder > .page-placeholder-card, :scope > .split-divider";

/** What may go from a row: its columns and its dividers. */
const leavers = ":scope > .page-column, :scope > .split-divider";

interface Box {
  readonly left: number;
  readonly top: number;
  readonly width: number;
  readonly height: number;
}

/** Where each of a row's columns and dividers stood in it before the change Svelte draws now. */
const boxes = new WeakMap<Element, Box>();

/** One row's layout motion: measured before each change it draws, and settled after it. */
export class RowMotion {
  #before = new Map<HTMLElement, DOMRect>();
  #running = new Map<HTMLElement, Animation>();

  /** Measures the row as it stands, before Svelte draws a change to it. */
  measure(row: HTMLElement | null | undefined) {
    this.#before.clear();
    if (!row?.isConnected) return;
    for (const element of row.querySelectorAll<HTMLElement>(movers)) this.#before.set(element, element.getBoundingClientRect());
    for (const element of row.querySelectorAll<HTMLElement>(leavers)) {
      if (getComputedStyle(element).position === "absolute") continue;
      const { offsetLeft: left, offsetTop: top, offsetWidth: width, offsetHeight: height } = element;
      boxes.set(element, { left, top, width, height });
    }
  }

  /**
   * Moves what the change moved from where it stood: a card as it says, and
   * the row's own parts on `timing`, the row's motion for the change.
   */
  settle(timing: Timing) {
    const measured = [...this.#before];
    this.#before.clear();
    for (const [element, from] of measured) {
      if (!element.isConnected) continue;
      const card = element.classList.contains("page-card");
      const layout = card ? cardLayouts.get(element) : undefined;
      if (card && !layout) continue;
      const moves = layout ? layout.timing() : timing;
      const positionOnly = element.classList.contains("split-divider");
      const previous = this.#running.get(element);
      this.#running.delete(element);
      previous?.cancel();
      const played = moves && !reducesMotion() ? this.#play(element, from, moves, positionOnly) : null;
      if (played) {
        layout?.started();
        this.#running.set(element, played);
        const done = () => {
          if (this.#running.get(element) !== played) return;
          this.#running.delete(element);
          layout?.finished();
        };
        played.onfinish = done;
        played.oncancel = done;
      } else if (previous) {
        layout?.finished();
      }
    }
  }

  #play(element: HTMLElement, from: DOMRect, timing: Timing, positionOnly: boolean): Animation | null {
    const { duration, delay, css } = timed(timing);
    if (duration === 0 && delay === 0) return null;
    const to = element.getBoundingClientRect();
    const dx = from.left + from.width / 2 - (to.left + to.width / 2);
    const dy = from.top + from.height / 2 - (to.top + to.height / 2);
    const sx = positionOnly || !to.width ? 1 : from.width / to.width;
    const sy = positionOnly || !to.height ? 1 : from.height / to.height;
    if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5 && Math.abs(sx - 1) < 0.005 && Math.abs(sy - 1) < 0.005) return null;
    return element.animate(
      [{ transform: `translate(${dx}px, ${dy}px) scale(${sx}, ${sy})` }, { transform: "translate(0px, 0px) scale(1, 1)" }],
      // It stands where it was through its delay, and keeps nothing once done.
      { duration, delay, easing: css, composite: "add", fill: "backwards" },
    );
  }
}

/**
 * `out:` for a row's columns and dividers, as `presence` with `popLayout`:
 * the part going is lifted out of the row where it stood before the change,
 * which Svelte has already drawn the newcomers of by the time it goes.
 */
export function liftOut(node: Element, options: PresenceOptions): TransitionConfig {
  const element = node as HTMLElement;
  const box = boxes.get(element);
  if (box && element.isConnected && getComputedStyle(element).position !== "absolute") {
    const lifted = {
      position: "absolute",
      left: `${box.left}px`,
      top: `${box.top}px`,
      width: `${box.width}px`,
      height: `${box.height}px`,
      margin: "0",
      pointerEvents: "none",
    };
    const { style } = element;
    const standing = Object.fromEntries(Object.keys(lifted).map((name) => [name, style[name as keyof typeof lifted]]));
    Object.assign(style, lifted);
    // A part that comes back before it has gone, which Svelte makes no longer
    // inert as it gives it back, stands in the row again.
    const returns = new MutationObserver(() => {
      if (element.inert) return;
      returns.disconnect();
      Object.assign(style, standing);
    });
    returns.observe(element, { attributes: true, attributeFilter: ["inert"] });
  }
  return presence(element, { ...options, pop: !box });
}
