import { type BrandColor, type BrandGradient, type SpaceBranding, type SpaceGradientKind, SpaceThemeModeKinds } from "@crest/contracts";
import type { ReactNode } from "react";

import { css, indigo } from "../branding";

/**
 * A Space's colors as the Mac's SpaceBranding+Fill draws them: each one
 * color, or a gradient of its kind toward its angle. A Space is two wells,
 * Background and Accent, the palette's first two colors, each running on
 * into the further colors its own gradient keeps; its third color, Pattern,
 * shows where a sidebar pattern draws it. A Space from before the wells may
 * draw its colors as one gradient, or give its icon a color of its own.
 */
export interface SpaceFill {
  /** The colors in order, one to three. */
  readonly colors: readonly BrandColor[];
  readonly kind: FillKind;
  /** Where a linear or angular fill runs: 0 left to right, 90 top to bottom. */
  readonly degrees: number;
}

/** CrestGradientKind: along a line, out from the middle, or around it. */
export type FillKind = "linear" | "radial" | "angular";

/** CrestColorFill.maximumColors. */
const maximumColors = 3;

function fill(colors: readonly BrandColor[], kind: FillKind = "linear", degrees = 90): SpaceFill {
  const kept = colors.slice(0, maximumColors);
  return { colors: kept.length > 0 ? kept : [indigo], kind, degrees };
}

/** The kind a Space's branding stores, where none is linear. */
function kindOf(stored: SpaceGradientKind | null | undefined): FillKind {
  return stored?.name === "radial" || stored?.name === "angular" ? stored.name : "linear";
}

/** `base` running into `gradient`'s colors, or plain without one. */
function into(base: BrandColor, gradient: BrandGradient | null | undefined): SpaceFill {
  if (!gradient || gradient.colors.colors.length === 0) return fill([base]);
  return fill([base, ...gradient.colors.colors], kindOf(gradient.kind), gradient.angle);
}

/** The palette's color at `slot`, with the gradient it runs into. */
export function slotFill(branding: SpaceBranding, slot: number): SpaceFill {
  const colors = branding.colors.colors;
  const base = colors[slot] ?? colors.at(-1) ?? indigo;
  return into(base, branding.colorGradients?.slots[slot]);
}

/** The sidebar's colors as one gradient, for a Space that draws them so. */
export function sidebarFill(branding: SpaceBranding): SpaceFill {
  const colors = branding.colors.colors;
  return fill(colors.length > 0 ? colors : [indigo], kindOf(branding.gradientKind), branding.gradientAngle);
}

/** The Space's Background, which the sidebar wears. */
export function backgroundFill(branding: SpaceBranding): SpaceFill {
  return branding.themeMode.kind === SpaceThemeModeKinds.Gradient ? sidebarFill(branding) : slotFill(branding, 0);
}

/** The Space's Accent: its crest's emblem and border, its icon and its highlights. An icon's own color keeps it until the Accent is set. */
export function accentFill(branding: SpaceBranding): SpaceFill {
  return branding.symbolColor ? into(branding.symbolColor, branding.symbolGradient) : slotFill(branding, 1);
}

/** The fill a crest layer drawn from palette entry `index` wears: the crest's own palette's, or the Space's. */
export function crestLayerFill(branding: SpaceBranding, index: number): SpaceFill {
  const palette = branding.crest.palette?.colors ?? [];
  if (palette.length === 0) return slotFill(branding, index);
  return into(palette[index] ?? palette[0], branding.crest.paletteGradients?.slots[index]);
}

/**
 * The colors the sidebar paints, which its text reads over: a solid sidebar
 * its Background and the colors that runs into, a pattern every color and
 * the colors each runs into, and a sidebar drawing its colors as one
 * gradient those colors. The Accent, which only the crest and highlights
 * wear on a solid sidebar, has no say.
 */
export function paintedColors(branding: SpaceBranding): readonly BrandColor[] {
  const colors = branding.colors.colors;
  if (colors.length === 0) return [indigo];
  if (branding.themeMode.kind === SpaceThemeModeKinds.Gradient) return colors;
  if (branding.bannerPattern.name === "solid") return backgroundFill(branding).colors;
  return colors.flatMap((_, slot) => slotFill(branding, slot).colors);
}

// MARK: - Drawing

/** A box a fill spans, in the drawing's own units. */
export interface FillBox { readonly x: number; readonly y: number; readonly width: number; readonly height: number }

/**
 * `fill` as an SVG paint over `box`: its color, or a gradient the returned
 * definition names `id`. A linear fill runs between the box's edges along its
 * angle, a radial one rings out from the middle to the box's edges, and an
 * angular one turns around the middle from its angle, back to its first
 * color. Every kind blends its colors as the Mac's perceptual gradients do.
 */
export function fillPaint(value: SpaceFill, id: string, box: FillBox): { readonly paint: string; readonly definition: ReactNode } {
  if (value.colors.length < 2) return { paint: css(value.colors[0] ?? indigo), definition: null };
  const at = (u: number, v: number) => ({ x: box.x + u * box.width, y: box.y + v * box.height });
  if (value.kind === "angular") {
    const stops = denseStops([...value.colors, value.colors[0]]);
    const wedges = 96;
    const center = at(0.5, 0.5);
    const reach = Math.hypot(box.width, box.height);
    const shapes: ReactNode[] = [];
    for (let wedge = 0; wedge < wedges; wedge++) {
      const from = ((value.degrees + (wedge / wedges) * 360) * Math.PI) / 180;
      const to = ((value.degrees + ((wedge + 1.02) / wedges) * 360) * Math.PI) / 180;
      const point = (angle: number) => `${center.x + Math.cos(angle) * reach},${center.y + Math.sin(angle) * reach}`;
      shapes.push(<polygon key={wedge} points={`${center.x},${center.y} ${point(from)} ${point(to)}`}
        fill={css(colorAlong(stops, (wedge + 0.5) / wedges))} />);
    }
    return {
      paint: `url(#${id})`,
      definition: (
        <pattern key={id} id={id} patternUnits="userSpaceOnUse" x={box.x} y={box.y} width={box.width} height={box.height}>
          <g transform={`translate(${-box.x} ${-box.y})`}>{shapes}</g>
        </pattern>
      ),
    };
  }
  const stops = denseStops(value.colors).map((stop, index) => (
    <stop key={index} offset={stop.location} stopColor={css(stop.color)} />
  ));
  if (value.kind === "radial") {
    const center = at(0.5, 0.5);
    return {
      paint: `url(#${id})`,
      definition: (
        <radialGradient key={id} id={id} gradientUnits="userSpaceOnUse" cx={center.x} cy={center.y} r={box.width / 2}
          gradientTransform={`translate(${center.x} ${center.y}) scale(1 ${box.height / Math.max(1, box.width)}) translate(${-center.x} ${-center.y})`}>
          {stops}
        </radialGradient>
      ),
    };
  }
  // SwiftUI's linear gradient from the unit point across the middle from its angle's to that one.
  const radians = (value.degrees * Math.PI) / 180;
  const end = at(0.5 + 0.5 * Math.cos(radians), 0.5 + 0.5 * Math.sin(radians));
  const start = at(0.5 - 0.5 * Math.cos(radians), 0.5 - 0.5 * Math.sin(radians));
  return {
    paint: `url(#${id})`,
    definition: (
      <linearGradient key={id} id={id} gradientUnits="userSpaceOnUse" x1={start.x} y1={start.y} x2={end.x} y2={end.y}>
        {stops}
      </linearGradient>
    ),
  };
}

/** The fill's color at `fraction` of the way along it, for the one color a small mark can wear. */
export function fillColorAt(value: SpaceFill, fraction: number): BrandColor {
  return value.colors.length < 2 ? value.colors[0] ?? indigo : colorAlong(denseStops(value.colors), fraction);
}

// MARK: - Perceptual blending

/** A gradient stop: its color, and where along the gradient it stands, from 0 to 1. */
interface Stop { readonly color: BrandColor; readonly location: number }

/**
 * The stops an SVG gradient draws for `colors`: the Mac's perceptual stops,
 * each span between them filled in with stops mixed in OKLab, since SVG
 * blends neighbors in sRGB where SwiftUI's perceptual gradients do not.
 */
function denseStops(colors: readonly BrandColor[]): readonly Stop[] {
  const coarse = blendingStops(colors);
  const steps = 6;
  const stops: Stop[] = [coarse[0]];
  for (let index = 1; index < coarse.length; index++) {
    const from = coarse[index - 1];
    const to = coarse[index];
    for (let step = 1; step <= steps; step++) {
      const amount = step / steps;
      stops.push({ color: mixOklab(from.color, to.color, amount), location: from.location + (to.location - from.location) * amount });
    }
  }
  return stops;
}

/** The color at `fraction` along `stops`, mixed in OKLab between the two around it. */
function colorAlong(stops: readonly Stop[], fraction: number): BrandColor {
  const after = stops.findIndex((stop) => stop.location >= fraction);
  if (after <= 0) return stops[Math.max(0, after)]?.color ?? indigo;
  const from = stops[after - 1];
  const to = stops[after];
  const span = to.location - from.location;
  return mixOklab(from.color, to.color, span > 0 ? (fraction - from.location) / span : 0);
}

/**
 * CrestPerceptualColor.blendingStops: the stops a gradient of `colors`
 * draws, evenly spaced, with stops between any two vivid neighbors whose
 * hues stand far apart, which turn around the wheel in small steps instead
 * of through gray, the short way unless that way crosses mud and the long
 * way doesn't.
 */
function blendingStops(colors: readonly BrandColor[]): readonly Stop[] {
  if (colors.length < 2) return colors.map((color) => ({ color, location: 0 }));
  const span = 1 / (colors.length - 1);
  const stops: Stop[] = [{ color: colors[0], location: 0 }];
  for (let index = 0; index < colors.length - 1; index++) {
    const a = lch(colors[index]);
    const b = lch(colors[index + 1]);
    let turn = shorterTurn(a.degrees, b.degrees);
    if (a.chroma >= perceptual.blendChroma && b.chroma >= perceptual.blendChroma && Math.abs(turn) > perceptual.blendTurn) {
      const other = turn > 0 ? turn - 360 : turn + 360;
      if (crossesMud(a, b, turn) && !crossesMud(a, b, other)) turn = other;
      const steps = Math.ceil(Math.abs(turn) / perceptual.blendStep);
      for (let step = 1; step < steps; step++) {
        const fraction = step / steps;
        const lightness = a.lightness + (b.lightness - a.lightness) * fraction;
        const hue = (a.degrees + turn * fraction) / 360;
        const chroma = Math.min(a.chroma + (b.chroma - a.chroma) * fraction, maximumChroma(lightness, hue));
        stops.push({ color: fromLch(lightness, chroma, hue), location: (index + fraction) * span });
      }
    }
    stops.push({ color: colors[index + 1], location: (index + 1) * span });
  }
  return stops;
}

/**
 * CrestColorHarmony.shade(of:): the color a tenth lighter in OKLCH, or a
 * tenth darker where it is already light, at its own chroma and hue, as far
 * as sRGB holds it. A solid sidebar's pattern wears its Background's shade.
 */
export function shadedColor(color: BrandColor): BrandColor {
  const { lightness, chroma, degrees } = lch(color);
  return fromLch(lightness < 0.86 ? lightness + 0.1 : lightness - 0.1, chroma, degrees);
}

/** CrestPerceptualColorMetrics. */
const perceptual = {
  gamutSteps: 18,
  chromaCeiling: 0.4,
  mudHues: [50, 125] as const,
  mudDepth: 0.2,
  mudChroma: 0.03,
  blendChroma: 0.04,
  blendTurn: 60,
  blendStep: 30,
  mudSamples: 12,
  gamutTolerance: 0.0001,
} as const;

/** Ottosson's sRGB cusp lightness every 10° of hue from 0: where each hue is most vivid. */
const cuspLightnesses = [
  0.647, 0.639, 0.632, 0.632, 0.681, 0.721, 0.756, 0.790, 0.825, 0.863, 0.909, 0.967,
  0.939, 0.910, 0.876, 0.874, 0.882, 0.889, 0.896, 0.902, 0.882, 0.841, 0.802, 0.762,
  0.717, 0.661, 0.574, 0.465, 0.489, 0.518, 0.552, 0.595, 0.648, 0.697, 0.675, 0.659,
];

export interface Lch { readonly lightness: number; readonly chroma: number; readonly degrees: number }

/** A color in OKLCH: its lightness, chroma, and hue in degrees. */
export function lch(color: BrandColor): Lch {
  const [l, a, b] = oklab(color);
  const hue = Math.atan2(b, a) / (2 * Math.PI);
  return { lightness: l, chroma: Math.hypot(a, b), degrees: (((hue % 1) + 1) % 1) * 360 };
}

function shorterTurn(start: number, end: number): number {
  const turn = (end - start) % 360;
  return turn > 180 ? turn - 360 : turn <= -180 ? turn + 360 : turn;
}

function crossesMud(a: Lch, b: Lch, turn: number): boolean {
  for (let sample = 1; sample < perceptual.mudSamples; sample++) {
    const fraction = sample / perceptual.mudSamples;
    const degrees = ((((a.degrees + turn * fraction) % 360) + 360) % 360);
    const lightness = a.lightness + (b.lightness - a.lightness) * fraction;
    const chroma = a.chroma + (b.chroma - a.chroma) * fraction;
    const muddy = chroma >= perceptual.mudChroma && degrees >= perceptual.mudHues[0] && degrees <= perceptual.mudHues[1]
      && lightness < cuspLightness(degrees) - perceptual.mudDepth;
    if (muddy) return true;
  }
  return false;
}

/** The OKLCH lightness at which the hue at `degrees` is most vivid in sRGB. */
export function cuspLightness(degrees: number): number {
  const position = ((((degrees % 360) + 360) % 360)) / 10;
  const below = Math.floor(position) % cuspLightnesses.length;
  const above = (below + 1) % cuspLightnesses.length;
  return cuspLightnesses[below] + (cuspLightnesses[above] - cuspLightnesses[below]) * (position - Math.floor(position));
}

/** The most chroma sRGB holds at `lightness` and `hue`, a share of a turn. */
export function maximumChroma(lightness: number, hue: number): number {
  let low = 0;
  let high: number = perceptual.chromaCeiling;
  for (let step = 0; step < perceptual.gamutSteps; step++) {
    const middle = (low + high) / 2;
    if (inGamut(lightness, middle, hue)) low = middle;
    else high = middle;
  }
  return low;
}

/** The sRGB color of an OKLCH color, its hue a share of a turn, giving up chroma until sRGB holds it. */
export function fromLch(lightness: number, chroma: number, hue: number): BrandColor {
  if (inGamut(lightness, chroma, hue)) return clamped(lightness, chroma, hue);
  let low = 0;
  let high = chroma;
  for (let step = 0; step < perceptual.gamutSteps; step++) {
    const middle = (low + high) / 2;
    if (inGamut(lightness, middle, hue)) low = middle;
    else high = middle;
  }
  return clamped(lightness, low, hue);
}

/** CrestPerceptualColor.mix: `start` `amount` of the way to `end`, in OKLab. */
function mixOklab(start: BrandColor, end: BrandColor, amount: number): BrandColor {
  const [l1, a1, b1] = oklab(start);
  const [l2, a2, b2] = oklab(end);
  const l = l1 + (l2 - l1) * amount;
  const a = a1 + (a2 - a1) * amount;
  const b = b1 + (b2 - b1) * amount;
  const mixed = clamped(l, Math.hypot(a, b), Math.atan2(b, a) / (2 * Math.PI));
  return { ...mixed, alpha: start.alpha + (end.alpha - start.alpha) * amount };
}

function oklab(color: BrandColor): [number, number, number] {
  const r = linear(color.red);
  const g = linear(color.green);
  const b = linear(color.blue);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  ];
}

function linearRgb(lightness: number, chroma: number, hue: number): [number, number, number] {
  const angle = hue * 2 * Math.PI;
  const a = chroma * Math.cos(angle);
  const b = chroma * Math.sin(angle);
  const l = (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (lightness - 0.0894841775 * a - 1.2914855480 * b) ** 3;
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
  ];
}

function inGamut(lightness: number, chroma: number, hue: number): boolean {
  const low = -perceptual.gamutTolerance;
  const high = 1 + perceptual.gamutTolerance;
  return linearRgb(lightness, chroma, hue).every((channel) => channel >= low && channel <= high);
}

function clamped(lightness: number, chroma: number, hue: number): BrandColor {
  const [r, g, b] = linearRgb(lightness, chroma, hue);
  return { red: encoded(r), green: encoded(g), blue: encoded(b), alpha: 1 };
}

/** CrestPerceptualColor.isMuddy: a warm hue well below where it is most vivid, the dark oranges, yellows and olives. */
export function isMuddy(color: Lch): boolean {
  return color.chroma >= perceptual.mudChroma && color.degrees >= perceptual.mudHues[0] && color.degrees <= perceptual.mudHues[1]
    && color.lightness < cuspLightness(color.degrees) - perceptual.mudDepth;
}

/** WCAG relative luminance. */
export function luminance(color: BrandColor): number {
  return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue);
}

/** WCAG contrast between two luminances. */
export function contrast(first: number, second: number): number {
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}

function linear(channel: number): number {
  return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
}

function encoded(channel: number): number {
  const held = Math.min(Math.max(channel, 0), 1);
  return held <= 0.0031308 ? 12.92 * held : 1.055 * held ** (1 / 2.4) - 0.055;
}
