import { motion as tokens, springEasing } from "@crest/design";
import { animateCommandPalette } from "../appearance.svelte";
import { presentationPickup } from "../motion";
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
 * The glass and its blur travel together. The contents keep their resting
 * layout behind a clip that follows the frame.
 */

/** The parts of an overlay palette the morph moves. */
export interface PaletteParts {
  readonly scrim: HTMLElement;
  /** The card, which lays its contents out at rest. */
  readonly card: HTMLElement;
  readonly glass: HTMLElement;
  /** What clips the contents to the frame. */
  readonly reveal: HTMLElement;
  readonly contents: HTMLElement;
}

/** BrowserCommandPaletteMetrics.morphContentScale. */
const contentScale = 0.97;

function reducesMotion(): boolean {
  return matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/** The visible field that hands its frame to the palette, including the focused card of a split. */
function visibleField(selector: string): HTMLElement | null {
  const field = document.querySelector<HTMLElement>(selector);
  const box = field?.getBoundingClientRect();
  return field && box && box.width > 0 && box.right > 0 && box.left < innerWidth && box.bottom > 0 && box.top < innerHeight ? field : null;
}

export function pageAddressField(): HTMLElement | null {
  return visibleField(".space-content-page:not([inert]) .page-column.focused .split-address-toolbar .address-field")
    ?? visibleField(".page-address-toolbar:not(.split-address-toolbar):not([inert]) .address-field");
}

function addressField(): HTMLElement | null {
  return pageAddressField() ?? visibleField(".sidebar-slot:not(.collapsed) .address-field");
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

function fullClip(card: HTMLElement): string {
  return `inset(0px round ${getComputedStyle(card).borderTopLeftRadius})`;
}

function appearance(parts: PaletteParts) {
  const style = (element: HTMLElement) => getComputedStyle(element);
  return {
    scrim: style(parts.scrim).opacity,
    glass: { opacity: style(parts.glass).opacity, transform: style(parts.glass).transform },
    reveal: { transform: style(parts.reveal).transform, clipPath: style(parts.reveal).clipPath },
    contents: { opacity: style(parts.contents).opacity, transform: style(parts.contents).transform },
  };
}

function cancelMorph(parts: PaletteParts) {
  for (const layer of [parts.glass, parts.reveal, parts.contents, parts.scrim]) {
    for (const animation of layer.getAnimations()) animation.cancel();
  }
}

/**
 * Brings a palette in, its card laid out where it rests. Answers when its
 * glass has settled; the field it grew out of stays handed off until the
 * palette leaves.
 */
export function openPalette(parts: PaletteParts, reversing: boolean): Promise<void> {
  // The scrim waits unseen until its card is laid out, and comes in with it.
  const now = reversing ? appearance(parts) : null;
  if (reversing) cancelMorph(parts);
  parts.card.style.removeProperty("visibility");
  parts.contents.style.removeProperty("visibility");
  parts.scrim.style.removeProperty("opacity");
  const field = addressField();
  const animates = !reducesMotion() && animateCommandPalette.current;
  const handoff = parts.card.classList.contains("dropping") ? presentationPickup.dropdown : presentationPickup.palette;
  const pickup = reversing ? 0 : handoff;
  const { frame, scrim, reveal, trailing } = paces();
  if (field) {
    field.style.setProperty("--palette-handoff-fade", animates ? `${reveal}ms` : "0ms");
    field.style.setProperty("--palette-field-leave", animates ? `${pickup}ms` : "0ms");
    field.style.setProperty("--palette-field-return", animates ? `${handoff + trailing}ms` : "0ms");
    setFieldHandedOff(true);
  }
  if (!animates) return Promise.resolve();
  const card = parts.card.getBoundingClientRect();
  const runs: Animation[] = [];
  const run = (element: HTMLElement, keyframes: Keyframe[], timing: KeyframeAnimationOptions) => {
    const animation = element.animate(keyframes, { fill: "backwards", ...timing, delay: pickup + Number(timing.delay ?? 0) });
    runs.push(animation);
    return animation;
  };
  run(parts.scrim, [{ opacity: now?.scrim ?? 0 }, { opacity: 1 }], { duration: scrim.duration, easing: scrim.easing });
  if (field) {
    const from = field.getBoundingClientRect();
    const radius = parseFloat(getComputedStyle(field).borderTopLeftRadius) || 0;
    run(parts.glass, [{ transform: now?.glass.transform ?? glassOn(from, card) }, { transform: "none" }], { duration: frame.duration, easing: frame.easing });
    run(parts.reveal, [{ transform: now?.reveal.transform ?? contentsOn(from, card), clipPath: now?.reveal.clipPath ?? clipTo(from, card, radius) }, { transform: "none", clipPath: fullClip(parts.card) }],
      { duration: frame.duration, easing: frame.easing });
  }
  // The glass takes over from the field as the frame leaves it.
  run(parts.glass, [{ opacity: now?.glass.opacity ?? 0 }, { opacity: 1 }], { duration: reveal, easing: "ease-out" });
  run(parts.contents, [now?.contents ?? { opacity: 0, transform: `scale(${contentScale})` }, { opacity: 1, transform: "none" }],
    { duration: reveal, delay: now ? 0 : trailing, easing: "ease-out" });
  return Promise.all(runs.map((animation) => animation.finished)).then(() => undefined, () => undefined);
}

/** Takes a palette away, shrinking it back into the field where one is on screen. Answers once it has gone. */
export function closePalette(parts: PaletteParts): Promise<void> {
  // The field comes back as the frame lands on it: its own transition waits out the frame's travel.
  setFieldHandedOff(false);
  if (reducesMotion() || !animateCommandPalette.current) {
    cancelMorph(parts);
    return Promise.resolve();
  }
  const { frame, scrim, reveal, trailing } = paces();
  const field = addressField();
  const card = parts.card.getBoundingClientRect();
  // A palette closing as it opens carries on from where each part stands.
  const now = appearance(parts);
  cancelMorph(parts);
  // A reversal during pickup goes straight back to the field.
  if (Number(now.glass.opacity) === 0 && Number(now.contents.opacity) === 0) {
    parts.card.style.visibility = "hidden";
    parts.scrim.style.opacity = "0";
    return Promise.resolve();
  }
  const atRest = Number(now.glass.opacity) === 1;
  const handoff = parts.card.classList.contains("dropping") ? presentationPickup.dropdown : presentationPickup.palette;
  const pickup = atRest ? handoff : 0;
  const runs: Animation[] = [];
  const run = (element: HTMLElement, keyframes: Keyframe[], timing: KeyframeAnimationOptions) => {
    const animation = element.animate(keyframes, { fill: "both", ...timing, delay: pickup + Number(timing.delay ?? 0) });
    runs.push(animation);
    return animation;
  };
  run(parts.scrim, [{ opacity: now.scrim }, { opacity: 0 }], { duration: scrim.duration, easing: scrim.easing });
  // The contents clear before the frame starts to shrink, and are drawn no more once they have.
  const cleared = run(parts.contents, [{ opacity: now.contents.opacity, transform: now.contents.transform }, { opacity: 0, transform: `scale(${contentScale})` }],
    { duration: reveal, easing: "ease-out" });
  void cleared.finished.then(() => parts.contents.style.setProperty("visibility", "hidden"), () => undefined);
  if (field) {
    const to = field.getBoundingClientRect();
    const radius = parseFloat(getComputedStyle(field).borderTopLeftRadius) || 0;
    run(parts.glass, [{ transform: now.glass.transform }, { transform: glassOn(to, card) }], { duration: frame.duration, easing: frame.easing });
    run(parts.reveal, [
      { transform: now.reveal.transform, clipPath: now.reveal.clipPath === "none" ? fullClip(parts.card) : now.reveal.clipPath },
      { transform: contentsOn(to, card), clipPath: clipTo(to, card, radius) },
    ], { duration: frame.duration, easing: frame.easing });
  }
  // The glass hands back to the field as the frame lands on it.
  run(parts.glass, [{ opacity: now.glass.opacity }, { opacity: 0 }], { duration: reveal, delay: trailing, easing: "ease-out" });
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
