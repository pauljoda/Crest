import type { SpaceState } from "@crest/contracts";
import { untrack } from "svelte";

import { readsLight } from "../branding";
import { interpolate, type PagerFrame, spacePager } from "./space-pager";

/**
 * The window's own chrome, which stays put as the Space pager moves: the title
 * bar, the address field's area and the Space strip's buttons (its picker
 * blends its own tone along the pager). Each Space's sidebar page
 * and card wear their own Space's look; these wear the look the pager stands
 * at, blended between the two Spaces either side of it, so their text and
 * surfaces change with the slide, as the Mac's chrome follows its pager,
 * rather than at once as the window takes the new Space.
 */
const chrome = ".title-bar, .sidebar-slot .address-area, .sidebar-slot .space-strip-utilities, .sidebar-slot .space-picker-overflow, .sidebar-slot .sidebar-toolbar";

/** The look's variables the chrome blends, as `.reads-light` and `.reads-dark` define them. */
const variables = [
  "--primary-rgb", "--fg", "--fg-secondary", "--surface", "--surface-selected", "--surface-border", "--field", "--sidebar-glass",
  "--sidebar-glass-hover",
] as const;

type Palette = ReadonlyMap<string, readonly number[]>;

/** Reads a look's variables as the stylesheet resolves them, so their values live in one place. */
function readPalette(root: HTMLElement, light: boolean): Palette {
  const probe = document.createElement("div");
  probe.className = `space-page ${light ? "reads-light" : "reads-dark"}`;
  probe.style.display = "none";
  root.append(probe);
  const style = getComputedStyle(probe);
  const palette = new Map<string, readonly number[]>();
  for (const name of variables) {
    // "rgb(255 255 255 / 0.94)" or "255 255 255": its numbers, with an alpha of 1 where none is given.
    const numbers = (style.getPropertyValue(name).match(/-?\d*\.?\d+/g) ?? []).map(Number);
    if (numbers.length >= 3) palette.set(name, numbers.length === 3 ? [...numbers, 1] : numbers.slice(0, 4));
  }
  probe.remove();
  return palette;
}

/** How far toward a light-ink look the pager stands: 0 at a dark-ink Space, 1 at a light-ink one. */
function lightness(frame: PagerFrame, looks: ReadonlyMap<string, boolean>): number | null {
  const at = (id: string | null | undefined) => (id && looks.has(id) ? (looks.get(id) ? 1 : 0) : null);
  if (frame.phase === "idle") return at(frame.originId);
  const sample = interpolate(frame.position, frame.order.length);
  if (!sample) return at(frame.originId);
  const lower = at(frame.order[sample.lower]);
  const upper = at(frame.order[sample.upper]);
  if (lower === null || upper === null) return at(frame.originId);
  return lower + (upper - lower) * sample.fraction;
}

function blend(dark: Palette, light: Palette, fraction: number): [string, string][] {
  const values: [string, string][] = [];
  for (const name of variables) {
    const from = dark.get(name);
    const to = light.get(name);
    if (!from || !to) continue;
    const mixed = from.map((value, index) => value + (to[index] - value) * fraction);
    const [r, g, b, a] = [Math.round(mixed[0]), Math.round(mixed[1]), Math.round(mixed[2]), Math.round(mixed[3] * 1000) / 1000];
    values.push([name, name === "--primary-rgb" ? `${r} ${g} ${b}` : `rgb(${r} ${g} ${b} / ${a})`]);
  }
  return values;
}

/**
 * Has the window's chrome under `root` wear the look the Space pager stands at, every frame it moves.
 * Call during initialization; `root` and `spaces` are read again whenever what they read changes.
 */
export function useChromeLook(root: () => HTMLElement | null | undefined, spaces: () => readonly SpaceState[]) {
  let looks = new Map<string, boolean>();
  let following: { readonly element: HTMLElement; readonly apply: (frame: PagerFrame, force?: boolean) => void; readonly stop: () => void } | null = null;
  // Once the window is drawn, its chrome follows the pager; and a Space's look
  // changing, or a part of the chrome drawn anew, as the address field is once
  // a list's search gives it back, takes the look at once: rewriting a
  // variable to the value it holds changes nothing.
  $effect(() => {
    const element = root();
    looks = new Map(spaces().map((space) => [space.id, readsLight(space.settings.look)]));
    untrack(() => {
      if (following && following.element !== element) {
        following.stop();
        following = null;
      }
      if (!element) return;
      if (!following) {
        const palettes = { dark: readPalette(element, false), light: readPalette(element, true) };
        let applied: string | null = null;
        const apply = (frame: PagerFrame, force = false) => {
          const fraction = lightness(frame, looks);
          if (fraction === null) return;
          // While the pager moves, the chrome's own color transitions stand
          // aside: restarted each frame, they would trail the blend.
          const key = `${fraction.toFixed(3)}${frame.phase === "idle" ? "" : " moving"}`;
          if (key === applied && !force) return;
          applied = key;
          const values = blend(palettes.dark, palettes.light, fraction);
          for (const target of element.querySelectorAll<HTMLElement>(chrome)) {
            for (const [name, value] of values) target.style.setProperty(name, value);
            target.classList.toggle("look-following", frame.phase !== "idle");
          }
        };
        following = { element, apply, stop: spacePager.subscribeFrames((frame) => apply(frame)) };
      }
      following.apply(spacePager.frame, true);
    });
  });
  $effect(() => () => {
    following?.stop();
    following = null;
  });
}
