import type { Spring } from "@crest/design";
import type { TransitionConfig } from "svelte/transition";

import { type Pose, reducesMotion, type Timed, timed, type Timing } from "../motion";

/**
 * Motion's own transitions, which a view falls back on where it names none,
 * as the React views did: opacity on a 0.3 s curve, a move on an underdamped
 * spring (stiffness 500, damping 25) and a scale on a firmer one (stiffness
 * 550, damping 30), each over its own time.
 */
export const motionFade: Timing = { duration: 0.3, ease: [0.25, 0.1, 0.35, 1] };

/** A spring of Motion's stiffness and damping (mass 1) as the tokens describe one. */
function spring(stiffness: number, damping: number): Spring {
  const omega = Math.sqrt(stiffness);
  return { type: "spring", visualDuration: (2 * Math.PI) / omega, bounce: 1 - damping / (2 * omega) };
}

const fade = timed(motionFade);
const move = timed(spring(500, 25));
const grow = timed(spring(550, 30));

export interface MotionDefaultsOptions {
  /** Where the element starts as it comes in, or ends as it goes; it rests fully opaque, unmoved and unscaled. */
  readonly pose: Pose;
  /** Whether it goes to the pose rather than coming from it. */
  readonly going?: boolean;
  /** Whether it comes or goes at once. */
  readonly instant?: boolean;
}

/**
 * A Svelte transition between `pose` and rest on Motion's default for each
 * property it changes, for `in:motionDefaults` and `out:motionDefaults` with
 * `going`. Under Reduce Motion it fades alone, as `presence` does.
 */
export function motionDefaults(_node: Element, { pose, going = false, instant = false }: MotionDefaultsOptions):
  TransitionConfig {
  if (instant) return {};
  const reduced = reducesMotion();
  const fades = pose.opacity !== undefined;
  const moves = !reduced && Boolean(pose.x || pose.y);
  const scales = !reduced && pose.scale !== undefined;
  const duration = Math.max(fades ? fade.duration : 0, moves ? move.duration : 0, scales ? grow.duration : 0);
  return {
    duration,
    css: (t) => {
      // Svelte runs `t` with time, toward 1 coming in and toward 0 going.
      const elapsed = (going ? 1 - t : t) * duration;
      const along = (curve: Timed) => curve.easing(Math.min(1, elapsed / curve.duration));
      const at = (from: number, rest: number, progress: number) =>
        (going ? rest + (from - rest) * progress : from + (rest - from) * progress);
      const parts: string[] = [];
      if (fades) parts.push(`opacity: ${at(pose.opacity!, 1, along(fade))}`);
      const transforms: string[] = [];
      if (moves) {
        const progress = along(move);
        transforms.push(`translate(${at(pose.x ?? 0, 0, progress)}px, ${at(pose.y ?? 0, 0, progress)}px)`);
      }
      if (scales) transforms.push(`scale(${at(pose.scale!, 1, along(grow))})`);
      if (transforms.length) parts.push(`transform: ${transforms.join(" ")}`);
      return parts.join("; ");
    },
  };
}
