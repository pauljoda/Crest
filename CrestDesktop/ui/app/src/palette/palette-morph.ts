import { motion as tokens, springEasing } from "@crest/design";
import { reader } from "../reactive";

/**
 * The overlay palette growing out of the sidebar's address field and
 * shrinking back into it, as the Mac's BrowserCommandSurfaceMorph paces it.
 * The card's frame and corners move from the field's to its own on the
 * sidebar's morph. Its glass takes over from the field as the frame leaves
 * it. Its contents keep their resting layout and show through the frame from
 * the top as it settles, fading in from a little under full size. Closing
 * runs the other way: the contents clear first, and the glass hands back to
 * the field as the frame lands on it. Where no field is on screen, the card
 * comes and goes where it rests; under Reduce Motion it does so at once.
 *
 * Everything moves on the compositor: the glass grows by transform, and the
 * contents ride with the frame's top edge, showing through a clip whose
 * corners keep their true radius. The
 * glass that moves has no backdrop blur, since a blur redrawn every frame
 * while the scrim fades across the whole window is more than an integrated
 * GPU draws in a frame. The resting glass, blur and all, fades in over it
 * once nothing behind it moves, and gives way to it as the palette closes.
 */

/** The parts of an overlay palette the morph moves. */
export interface PaletteParts {
  readonly scrim: HTMLElement;
  /** The card, which lays its contents out at rest. */
  readonly card: HTMLElement;
  /** The glass that moves, without a backdrop blur. */
  readonly moving: HTMLElement;
  /** The resting glass, with its blur. */
  readonly resting: HTMLElement;
  /** What clips the contents to the frame. */
  readonly reveal: HTMLElement;
  readonly contents: HTMLElement;
}

/** BrowserCommandPaletteMetrics.morphContentScale. */
const contentScale = 0.97;
/** The card's corner radius at rest, as the overlay presentation's. */
const restingRadius = 26;

function reducesMotion(): boolean {
  return matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/** The address field of the sidebar the window shows, while it is on screen, which the card grows out of. */
function addressField(): HTMLElement | null {
  const field = document.querySelector<HTMLElement>(".sidebar-slot:not(.collapsed) .address-field");
  if (!field) return null;
  const frame = field.getBoundingClientRect();
  const inWindow = frame.width > 0 && frame.right > 0 && frame.left < innerWidth && frame.bottom > 0 && frame.top < innerHeight;
  return inWindow ? field : null;
}

/** The pace of each part, as BrowserCommandSurfaceMorph's. */
function paces() {
  const frame = springEasing(tokens.sidebarMorph);
  // The scrim stops once within a hundredth of its own fade, which no one
  // sees, rather than redrawing the whole window for the spring's last tail.
  const scrim = springEasing(tokens.sidebarMorph, 0.01);
  const reveal = tokens.contentReveal.duration * 1000;
  // The trailing fade finishes as the frame visually settles.
  const trailing = tokens.sidebarMorph.visualDuration * 1000 - reveal;
  return { frame, scrim, reveal, trailing };
}

/** The transform that puts the card's glass on `field`, from its place at rest. */
function glassOn(field: DOMRect, card: DOMRect): string {
  return `translate(${field.left - card.left}px, ${field.top - card.top}px) scale(${field.width / card.width}, ${field.height / card.height})`;
}

/**
 * Where the contents stand while the frame is `field`'s, as the Mac's sit in
 * the morphing frame: from its top edge, centred across it.
 */
function contentsOn(field: DOMRect, card: DOMRect): string {
  return `translate(${field.left + field.width / 2 - (card.left + card.width / 2)}px, ${field.top - card.top}px)`;
}

/** The clip that shows the contents, standing there, only within `field`'s frame and corners. */
function clipTo(field: DOMRect, card: DOMRect, radius: number): string {
  const side = (card.width - field.width) / 2;
  return `inset(0px ${side}px ${card.height - field.height}px ${side}px round ${radius}px)`;
}

const fullClip = `inset(0px round ${restingRadius}px)`;

/**
 * The contents' fade waiting to begin, for each palette. Until then they are
 * drawn no more than they must be: at no opacity, and all but the query
 * field hidden. The compositor still draws unseen what the clip and the fade
 * hold, each frame, in passes as large as what they hold, which on top of
 * the scrim's redraw an integrated GPU can't afford for the whole card. The
 * field stays, at no opacity, so it keeps the keyboard.
 */
const waitingReveals = new WeakMap<HTMLElement, ReturnType<typeof setTimeout>>();

/**
 * Brings a palette in, its card laid out where it rests. Answers when its
 * glass has settled; the field it grew out of stays handed off until the
 * palette leaves.
 */
export function openPalette(parts: PaletteParts): Promise<void> {
  // The scrim waits unseen until its card is laid out, and comes in with it.
  parts.scrim.style.removeProperty("opacity");
  if (reducesMotion()) return Promise.resolve();
  const { frame, scrim, reveal, trailing } = paces();
  const field = addressField();
  const card = parts.card.getBoundingClientRect();
  if (field) setFieldHandedOff(true);
  parts.card.classList.add("morphing");
  const runs: Animation[] = [];
  const run = (element: HTMLElement, keyframes: Keyframe[], timing: KeyframeAnimationOptions) => {
    const animation = element.animate(keyframes, { fill: "backwards", ...timing });
    runs.push(animation);
    return animation;
  };
  run(parts.scrim, [{ opacity: 0 }, { opacity: 1 }], { duration: scrim.duration, easing: scrim.easing });
  if (field) {
    const from = field.getBoundingClientRect();
    const radius = parseFloat(getComputedStyle(field).borderTopLeftRadius) || 0;
    run(parts.moving, [{ transform: glassOn(from, card) }, { transform: "none" }], { duration: frame.duration, easing: frame.easing });
    run(parts.reveal, [{ transform: contentsOn(from, card), clipPath: clipTo(from, card, radius) }, { transform: "none", clipPath: fullClip }],
      { duration: frame.duration, easing: frame.easing });
  }
  // The glass takes over from the field as the frame leaves it.
  run(parts.moving, [{ opacity: 0 }, { opacity: 1 }], { duration: reveal, easing: "ease-out" });
  // The contents appear once the frame has nearly settled.
  parts.contents.style.opacity = "0";
  parts.contents.classList.add("waiting");
  waitingReveals.set(parts.contents, setTimeout(() => {
    waitingReveals.delete(parts.contents);
    parts.contents.classList.remove("waiting");
    run(parts.contents, [{ opacity: 0, transform: `scale(${contentScale})` }, { opacity: 1, transform: "none" }],
      { duration: reveal, easing: "ease-out" });
    parts.contents.style.removeProperty("opacity");
  }, trailing));
  // The blur comes in once nothing behind the card moves.
  const blur = run(parts.resting, [{ opacity: 0 }, { opacity: 1 }], { duration: reveal, delay: frame.duration, easing: "ease-out" });
  return blur.finished.then(() => parts.card.classList.remove("morphing"), () => undefined);
}

/** Takes a palette away, shrinking it back into the field where one is on screen. Answers once it has gone. */
export function closePalette(parts: PaletteParts): Promise<void> {
  // The field comes back as the frame lands on it: its own transition waits out the frame's travel.
  setFieldHandedOff(false);
  if (reducesMotion()) return Promise.resolve();
  const { frame, scrim, reveal, trailing } = paces();
  const field = addressField();
  const card = parts.card.getBoundingClientRect();
  // A palette closing as it opens carries on from where each part stands.
  const style = (element: HTMLElement) => getComputedStyle(element);
  const now = {
    scrim: style(parts.scrim).opacity,
    moving: { opacity: style(parts.moving).opacity, transform: style(parts.moving).transform },
    reveal: { transform: style(parts.reveal).transform, clipPath: style(parts.reveal).clipPath },
    contents: { opacity: style(parts.contents).opacity, transform: style(parts.contents).transform },
  };
  const opening = parts.card.classList.contains("morphing");
  clearTimeout(waitingReveals.get(parts.contents));
  waitingReveals.delete(parts.contents);
  parts.contents.classList.remove("waiting");
  for (const animation of [...parts.card.getAnimations({ subtree: true }), ...parts.scrim.getAnimations()]) animation.cancel();
  parts.card.classList.add("morphing");
  const runs: Animation[] = [];
  const run = (element: HTMLElement, keyframes: Keyframe[], timing: KeyframeAnimationOptions) => {
    const animation = element.animate(keyframes, { fill: "forwards", ...timing });
    runs.push(animation);
    return animation;
  };
  // The moving glass stands in for the resting one at once: nothing about
  // the card may redraw the blur while the scrim fades.
  run(parts.resting, [{ opacity: 0 }, { opacity: 0 }], { duration: frame.duration });
  run(parts.scrim, [{ opacity: now.scrim }, { opacity: 0 }], { duration: scrim.duration, easing: scrim.easing });
  // The contents clear before the frame starts to shrink, and are drawn no more once they have.
  const cleared = run(parts.contents, [{ opacity: now.contents.opacity, transform: now.contents.transform }, { opacity: 0, transform: `scale(${contentScale})` }],
    { duration: reveal, easing: "ease-out" });
  void cleared.finished.then(() => parts.contents.style.setProperty("visibility", "hidden"), () => undefined);
  if (field) {
    const to = field.getBoundingClientRect();
    const radius = parseFloat(getComputedStyle(field).borderTopLeftRadius) || 0;
    run(parts.moving, [{ transform: now.moving.transform }, { transform: glassOn(to, card) }], { duration: frame.duration, easing: frame.easing });
    run(parts.reveal, [
      { transform: now.reveal.transform, clipPath: now.reveal.clipPath === "none" ? fullClip : now.reveal.clipPath },
      { transform: contentsOn(to, card), clipPath: clipTo(to, card, radius) },
    ], { duration: frame.duration, easing: frame.easing });
  }
  // The glass hands back to the field as the frame lands on it.
  run(parts.moving, [{ opacity: opening ? now.moving.opacity : "1" }, { opacity: 0 }], { duration: reveal, delay: trailing, easing: "ease-out" });
  return Promise.all(runs.map((animation) => animation.finished)).then(() => undefined, () => undefined);
}

// MARK: - The overlay's presence

/**
 * Whether an overlay palette is on screen, from its arrival until it has
 * gone. A Start Page's own palette beneath it drops its blur meanwhile: under
 * the scrim, and mostly under the overlay's card, it blurs only the Space's
 * smooth banner, and redrawn with every frame of the overlay's morph it costs
 * an integrated GPU frames.
 */
let overlayPresent = false;
const overlayListeners = new Set<() => void>();

export function setOverlayPresent(value: boolean) {
  if (overlayPresent === value) return;
  overlayPresent = value;
  for (const listener of overlayListeners) listener();
}

const readOverlayPresent = reader((listener) => {
  overlayListeners.add(listener);
  return () => overlayListeners.delete(listener);
}, () => overlayPresent);

/** Whether the overlay palette is up, followed by the expression that reads it. */
export function useOverlayPresent(): boolean {
  return readOverlayPresent();
}

// MARK: - The field's hand-off

/**
 * Whether the sidebar's address field has handed off to the palette, as the
 * Mac's BrowserCommandPaletteHandoff: the field keeps its place, faded out,
 * while the palette that grew out of it is open.
 */
let handedOff = false;
const listeners = new Set<() => void>();

function setFieldHandedOff(value: boolean) {
  if (handedOff === value) return;
  handedOff = value;
  for (const listener of listeners) listener();
}

/** Whether the address field is handed off to an open palette now. */
const readFieldHandedOff = reader((listener) => {
  listeners.add(listener);
  return () => listeners.delete(listener);
}, () => handedOff);

export function useFieldHandedOff(): boolean {
  return readFieldHandedOff();
}
