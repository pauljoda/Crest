import { springCurve, springEasing, type Spring } from "@crest/design";
import { prefersReducedMotion } from "svelte/motion";
import type { TransitionConfig } from "svelte/transition";

/**
 * Crest's motion in Svelte: the design tokens' springs and curves as
 * transitions for what comes and goes, and as timings for the animations the
 * compositor runs from keyframes or CSS transitions.
 *
 * A token is a spring, SwiftUI's duration and bounce, or a curve of a
 * duration in seconds, as `@crest/design`'s `motion` names them.
 */
export type Timing =
  | (Spring & { readonly delay?: number })
  | { readonly duration: number; readonly ease?: Ease; readonly delay?: number };

/** A curve by name, as the tokens name them, or a cubic Bézier's control points. */
export type Ease = "linear" | "easeIn" | "easeOut" | "easeInOut" | readonly [number, number, number, number];

/** A token resolved for Svelte and for the compositor. */
export interface Timed {
  /** How long it takes, in milliseconds. */
  readonly duration: number;
  /** How long it waits before it starts, in milliseconds. */
  readonly delay: number;
  /** How far along it stands at a fraction of its time, for Svelte's transitions and tweens. */
  readonly easing: (t: number) => number;
  /** The same easing as CSS, for `element.animate` and CSS transitions. */
  readonly css: string;
}

const curves: Record<Exclude<Ease, readonly number[]>, readonly [number, number, number, number]> = {
  linear: [0, 0, 1, 1],
  easeIn: [0.42, 0, 1, 1],
  easeOut: [0, 0, 0.58, 1],
  easeInOut: [0.42, 0, 0.58, 1],
};

/** A token's duration, delay and easing in the forms Svelte and the compositor take. */
export function timed(timing: Timing): Timed {
  const delay = Math.round((timing.delay ?? 0) * 1000);
  if ("type" in timing) {
    const { position, duration } = springCurve(timing);
    const seconds = duration / 1000;
    return { duration: Math.round(duration), delay, easing: (t) => (t >= 1 ? 1 : position(t * seconds)), css: springEasing(timing).easing };
  }
  const points = typeof timing.ease === "string" || timing.ease === undefined ? curves[timing.ease ?? "easeInOut"] : timing.ease;
  return {
    duration: Math.round(timing.duration * 1000),
    delay,
    easing: bezier(...points),
    css: `cubic-bezier(${points.join(", ")})`,
  };
}

/** A token as a CSS transition's duration, delay and easing, for `transition` on the property it moves. */
export function transitionStyle(property: string, timing: Timing): string {
  const { duration, delay, css } = timed(timing);
  return `${property} ${reducesMotion() ? 0 : duration}ms ${css} ${delay}ms`;
}

/** Whether the person asked the system for less motion, followed by the expression that reads it. */
export function reducesMotion(): boolean {
  return prefersReducedMotion.current;
}

/**
 * Where something stands when it is not yet there or has gone, as Motion's
 * `initial` and `exit` named it. Lengths are pixels, angles degrees; what a
 * pose leaves out stays as the element rests.
 */
export interface Pose {
  readonly opacity?: number;
  readonly x?: number;
  readonly y?: number;
  readonly scale?: number;
  readonly scaleX?: number;
  readonly scaleY?: number;
  readonly rotate?: number;
  readonly blur?: number;
}

export interface PresenceOptions {
  /** Where the element starts as it comes in, or ends as it goes. */
  readonly pose: Pose;
  readonly timing: Timing;
  /**
   * Takes a going element out of the layout as it starts to go, so what
   * stays moves into its place at once, as Motion's `popLayout` did. Its
   * offset parent must be positioned.
   */
  readonly pop?: boolean;
  /** Where its scale grows from, as CSS's `transform-origin`. */
  readonly origin?: string;
  /** The pose when the person asked for less motion; by default the pose's opacity alone. */
  readonly reduced?: Pose;
}

/**
 * A Svelte transition between `pose` and where the element rests, for
 * `in:presence` and `out:presence`: it comes in from the pose and goes out to
 * it, on the token's spring or curve, run by the compositor.
 */
export function presence(node: Element, options: PresenceOptions): TransitionConfig {
  const element = node as HTMLElement;
  const pose = reducesMotion() ? (options.reduced ?? { opacity: options.pose.opacity }) : options.pose;
  const { duration, delay, easing } = timed(options.timing);
  const style = getComputedStyle(element);
  if (options.pop && element.isConnected && style.position !== "absolute" && style.position !== "fixed") pop(element);
  const resting = Number(style.opacity);
  const base = style.transform === "none" ? "" : style.transform;
  if (options.origin) element.style.transformOrigin = options.origin;
  return {
    duration,
    delay,
    easing,
    css: (t) => poseStyle(pose, t, resting, base),
  };
}

/** The style of an element `t` of the way from `pose` to where it rests. */
export function poseStyle(pose: Pose, t: number, restingOpacity = 1, base = ""): string {
  const u = 1 - t;
  const parts: string[] = [];
  if (pose.opacity !== undefined) parts.push(`opacity: ${pose.opacity * u + restingOpacity * t}`);
  const moves: string[] = [];
  if (pose.x || pose.y) moves.push(`translate(${(pose.x ?? 0) * u}px, ${(pose.y ?? 0) * u}px)`);
  if (pose.scale !== undefined) moves.push(`scale(${pose.scale * u + t})`);
  if (pose.scaleX !== undefined || pose.scaleY !== undefined) {
    moves.push(`scale(${(pose.scaleX ?? 1) * u + t}, ${(pose.scaleY ?? 1) * u + t})`);
  }
  if (pose.rotate) moves.push(`rotate(${pose.rotate * u}deg)`);
  if (moves.length) parts.push(`transform: ${base} ${moves.join(" ")}`);
  if (pose.blur) parts.push(`filter: blur(${pose.blur * u}px)`);
  return parts.join("; ");
}

/**
 * Animates `element` from `pose` to where it rests, or back, on the
 * compositor: for an element that stays while its look changes, as Motion's
 * `animate` did when its target moved. Answers the running animation.
 */
export function animatePose(element: Element, from: Pose, to: Pose, timing: Timing): Animation {
  const { duration, delay, css } = timed(timing);
  const fades = from.opacity !== undefined || to.opacity !== undefined;
  const moves = [from, to].some((pose) => pose.x || pose.y || pose.scale !== undefined || pose.scaleX !== undefined
    || pose.scaleY !== undefined || pose.rotate);
  const blurs = Boolean(from.blur || to.blur);
  const keyframe = (pose: Pose): Keyframe => {
    const frame: Keyframe = {};
    if (fades) frame.opacity = pose.opacity ?? 1;
    if (moves) {
      const scaleX = (pose.scaleX ?? 1) * (pose.scale ?? 1);
      const scaleY = (pose.scaleY ?? 1) * (pose.scale ?? 1);
      frame.transform = `translate(${pose.x ?? 0}px, ${pose.y ?? 0}px) scale(${scaleX}, ${scaleY}) rotate(${pose.rotate ?? 0}deg)`;
    }
    if (blurs) frame.filter = `blur(${pose.blur ?? 0}px)`;
    return frame;
  };
  return element.animate([keyframe(from), keyframe(to)], {
    duration: reducesMotion() ? 0 : duration,
    delay,
    easing: css,
    fill: "both",
  });
}

/** Lifts a going element out of the layout where it stands. */
function pop(element: HTMLElement): void {
  const { offsetLeft, offsetTop, offsetWidth, offsetHeight } = element;
  Object.assign(element.style, {
    position: "absolute",
    left: `${offsetLeft}px`,
    top: `${offsetTop}px`,
    width: `${offsetWidth}px`,
    height: `${offsetHeight}px`,
    margin: "0",
    pointerEvents: "none",
  });
}

/** A cubic Bézier easing through (0, 0), the two control points, and (1, 1). */
function bezier(x1: number, y1: number, x2: number, y2: number): (t: number) => number {
  if (x1 === y1 && x2 === y2) return (t) => t;
  const at = (a: number, b: number, t: number) => ((1 - 3 * b + 3 * a) * t + (3 * b - 6 * a)) * t * t + 3 * a * t;
  const slope = (a: number, b: number, t: number) => 3 * (1 - 3 * b + 3 * a) * t * t + 2 * (3 * b - 6 * a) * t + 3 * a;
  return (x) => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    let t = x;
    for (let step = 0; step < 8; step++) {
      const error = at(x1, x2, t) - x;
      const gradient = slope(x1, x2, t);
      if (Math.abs(error) < 1e-6) break;
      if (Math.abs(gradient) < 1e-6) break;
      t -= error / gradient;
    }
    let low = 0;
    let high = 1;
    while (Math.abs(at(x1, x2, t) - x) > 1e-6 && high - low > 1e-7) {
      if (at(x1, x2, t) < x) low = t;
      else high = t;
      t = (low + high) / 2;
    }
    return at(y1, y2, t);
  };
}
