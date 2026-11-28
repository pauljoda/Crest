import { untrack } from "svelte";
import type { AnimationConfig } from "svelte/animate";

import { reducesMotion, timed, type Timing } from "./motion";

/**
 * Motion's `layout`, in Svelte: an element that changes place or size moves
 * there on a token's spring instead of jumping, its old frame measured before
 * Svelte updates the DOM and the difference played back on the compositor.
 */

/**
 * For the rows of a keyed `{#each}`, as `animate:flip={tokens.collection}`:
 * a row the list reorders slides from where it stood to its new place.
 */
export function flip(node: Element, { from, to }: { from: DOMRect; to: DOMRect }, timing: Timing): AnimationConfig {
  const { duration, delay, easing } = timed(timing);
  const style = getComputedStyle(node);
  const base = style.transform === "none" ? "" : style.transform;
  const dx = from.left + from.width / 2 - (to.left + to.width / 2);
  const dy = from.top + from.height / 2 - (to.top + to.height / 2);
  const sx = to.width ? from.width / to.width : 1;
  const sy = to.height ? from.height / to.height : 1;
  return {
    duration: reducesMotion() ? 0 : duration,
    delay,
    easing,
    css: (t, u) => `transform: ${base} translate(${dx * u}px, ${dy * u}px) scale(${sx + (1 - sx) * t}, ${sy + (1 - sy) * t})`,
  };
}

export interface LayoutMotionOptions {
  /** The element that moves, such as a `bind:this` target. */
  readonly element: () => HTMLElement | null | undefined;
  /**
   * Reads what moves it: each time it reads something new, the element
   * moves from its old frame to its new one. Only what this component
   * renders runs after this measures; a move a parent causes is drawn there.
   */
  readonly track: () => unknown;
  /** The spring or curve it moves on, or null for a change that jumps. */
  readonly timing: () => Timing | null;
  /** Whether it only changes place, as Motion's `layout="position"`, keeping its size as it is. */
  readonly positionOnly?: boolean;
}

/** Moves an element from where it stood to where it stands, for a change this component renders. Call during initialization. */
export function layoutMotion(options: LayoutMotionOptions): void {
  let before: DOMRect | null = null;
  let running: Animation | null = null;
  $effect.pre(() => {
    options.track();
    const element = untrack(options.element);
    before = element?.isConnected ? element.getBoundingClientRect() : null;
  });
  $effect(() => {
    options.track();
    untrack(() => {
      const element = options.element();
      const timing = options.timing();
      const from = before;
      before = null;
      running?.cancel();
      running = null;
      if (!element || !from || !timing || reducesMotion()) return;
      const to = element.getBoundingClientRect();
      // A move that also scales goes center to center; one that keeps its new size moves its top-left corner, as
      // Motion's `layout="position"` lays the old box out at the new size from where it began.
      const dx = options.positionOnly ? from.left - to.left : from.left + from.width / 2 - (to.left + to.width / 2);
      const dy = options.positionOnly ? from.top - to.top : from.top + from.height / 2 - (to.top + to.height / 2);
      const sx = options.positionOnly || !to.width ? 1 : from.width / to.width;
      const sy = options.positionOnly || !to.height ? 1 : from.height / to.height;
      if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5 && Math.abs(sx - 1) < 0.005 && Math.abs(sy - 1) < 0.005) return;
      const { duration, delay, css } = timed(timing);
      running = element.animate(
        [{ transform: `translate(${dx}px, ${dy}px) scale(${sx}, ${sy})` }, { transform: "translate(0px, 0px) scale(1, 1)" }],
        { duration, delay, easing: css, composite: "add" },
      );
      running.onfinish = () => {
        running = null;
      };
    });
  });
}
