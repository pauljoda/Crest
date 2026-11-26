import type { BrandColor } from "@crest/contracts";

import { contrast, cuspLightness, fromLch, isMuddy, lch, luminance, maximumChroma, type SpaceFill } from "./space-fills";

/**
 * The Mac's color popover models: a color as the wheel reads it
 * (CrestColorWheelPoint), where Crest puts the colors it adds to a gradient
 * (CrestColorHarmony), and the fill's colors as handles that are added,
 * taken out and moved, alone or together (CrestColorStops).
 */

// MARK: - Wheel points

/** How near black or white Brightness comes, which looks black or white but keeps the color's hue and vibrancy. */
export const edgeLightness = 0.004;

/**
 * CrestColorWheelPoint: a color's HSL hue, the angle round the wheel from
 * red at the top clockwise; its saturation, how far out from the gray
 * center it sits; and its lightness, which the wheel is drawn at.
 */
export interface WheelPoint {
  /** From 0 to 1. */
  readonly hue: number;
  /** From 0 for gray at the center to 1 at the rim. */
  readonly vibrancy: number;
  readonly lightness: number;
}

const clampUnit = (value: number) => Math.min(Math.max(value, 0), 1);

export function wheelPoint(hue: number, vibrancy: number, lightness: number): WheelPoint {
  const turned = hue % 1;
  return { hue: turned < 0 ? turned + 1 : turned, vibrancy: clampUnit(vibrancy), lightness: clampUnit(lightness) };
}

/** The point at `x`, `y` on a wheel of radius 1 centered on the origin, y running down; past the rim takes the rim. */
export function wheelPointAt(x: number, y: number, lightness: number): WheelPoint {
  return wheelPoint(Math.atan2(x, -y) / (2 * Math.PI), Math.hypot(x, y), lightness);
}

/** Where `point` sits on a wheel of radius 1 centered on the origin, y running down. */
export function wheelPosition(point: WheelPoint): { readonly x: number; readonly y: number } {
  const angle = point.hue * 2 * Math.PI;
  return { x: Math.sin(angle) * point.vibrancy, y: -Math.cos(angle) * point.vibrancy };
}

/** `color` as the wheel reads it. */
export function readWheel(color: BrandColor): WheelPoint {
  const high = Math.max(color.red, color.green, color.blue);
  const low = Math.min(color.red, color.green, color.blue);
  const lightness = (high + low) / 2;
  const spread = high - low;
  let hue = 0;
  if (spread > 0) {
    if (high === color.red) hue = ((color.green - color.blue) / spread) % 6;
    else if (high === color.green) hue = (color.blue - color.red) / spread + 2;
    else hue = (color.red - color.green) / spread + 4;
    hue /= 6;
  }
  const room = 1 - Math.abs(2 * lightness - 1);
  return wheelPoint(hue, room > 0 ? spread / room : 0, lightness);
}

/** The color at `point`. */
export function wheelColor(point: WheelPoint): BrandColor {
  const chroma = (1 - Math.abs(2 * point.lightness - 1)) * point.vibrancy;
  const sector = point.hue * 6;
  const second = chroma * (1 - Math.abs((sector % 2) - 1));
  const match = point.lightness - chroma / 2;
  const [red, green, blue] = [
    [chroma, second, 0],
    [second, chroma, 0],
    [0, chroma, second],
    [0, second, chroma],
    [second, 0, chroma],
    [chroma, 0, second],
  ][Math.trunc(sector) % 6];
  return { red: red + match, green: green + match, blue: blue + match, alpha: 1 };
}

/** `point`'s hue and vibrancy at `lightness`. */
export function withLightness(point: WheelPoint, lightness: number): WheelPoint {
  return wheelPoint(point.hue, point.vibrancy, lightness);
}

/** BrandColor.matches: the same color within what the eye can't tell apart. */
export function sameColor(left: BrandColor, right: BrandColor): boolean {
  const tolerance = 0.004;
  return Math.abs(left.red - right.red) <= tolerance && Math.abs(left.green - right.green) <= tolerance
    && Math.abs(left.blue - right.blue) <= tolerance;
}

// MARK: - Harmony

/** CrestColorHarmonyMetrics. */
const harmonyMetrics = {
  shadeStep: 0.1,
  achromaticChroma: 0.012,
  tintedChroma: 0.04,
  hueStep: 45,
  secondStep: 0.12,
  thirdStep: 0.08,
  leastStep: 0.06,
  farthestStep: 0.18,
  cuspPull: 0.25,
  gamutShare: 0.9,
  nearWhite: 0.86,
  lightestColor: 0.92,
  lightestGray: 0.95,
  darkestGray: 0.18,
  mudLift: 0.15,
  mudHues: [50, 125] as const,
  textContrast: 4.5,
  textNudge: 0.005,
  textSteps: 80,
  darkLeast: 0.07,
  lightLeast: 0.09,
  pastelLeast: 0.05,
  pastel: 0.85,
  mostAbove: 0.1,
  tintedLeast: 0.03,
  tintedMost: 0.06,
  tie: 0.05,
  contrastingTurn: 120,
  flatStep: 0.02,
} as const;

/** A color Crest placed, with the way its lightness went. */
interface Placed {
  readonly lightness: number;
  readonly chroma: number;
  readonly degrees: number;
  readonly direction: number;
}

const placedLch = (placed: Placed) => ({
  lightness: clampUnit(placed.lightness),
  chroma: Math.max(placed.chroma, 0),
  degrees: (((placed.degrees % 360) + 360) % 360),
});
const placedColor = (placed: Placed) => {
  const color = placedLch(placed);
  return fromLch(color.lightness, color.chroma, color.degrees / 360);
};

/**
 * CrestColorHarmony, read from one color: each added color turns 45° on
 * from the last, steps lighter from a dark or middling color and darker
 * from a near-white one, leaning toward where its hue is most vivid, keeps
 * the text over it at 4.5:1, and is vivid enough to show within what sRGB
 * holds; a muted color keeps muted partners and a gray keeps gray ones.
 */
class Harmony {
  readonly isDark: boolean;
  private readonly textFloor: number;

  constructor(color: BrandColor, private readonly isAchromatic: boolean, readonly isTinted: boolean) {
    const reading = luminance(color);
    const onWhite = contrast(1, reading);
    const onBlack = contrast(0, reading);
    this.isDark = onWhite >= onBlack;
    this.textFloor = Math.min(harmonyMetrics.textContrast, this.isDark ? onWhite : onBlack);
  }

  /** The color at `degrees` a `step` of lightness on from `lightness` in `direction`; one that barely moves goes the other way when `mayFlip`. */
  place(lightness: number, reference: number, degrees: number, direction: number, step: number, mayFlip: boolean): Placed {
    const target = lightness + direction * step;
    let pull = this.isAchromatic ? 0 : harmonyMetrics.cuspPull * (cuspLightness(degrees) - target) * (this.isTinted ? 0.5 : 1);
    if (pull * direction < 0) pull = direction * Math.max(pull * direction, -step / 2);
    const placed = this.settle(target + pull, lightness, reference, degrees);
    if (mayFlip && (placed.lightness - lightness) * direction < harmonyMetrics.leastStep) {
      const flipped = this.settle(lightness - direction * step, lightness, reference, degrees);
      return { ...flipped, degrees, direction: -direction };
    }
    return { ...placed, degrees, direction };
  }

  /** The chroma an added color wants beside colors of `reference` chroma. */
  wantedChroma(lightness: number, reference: number): number {
    if (this.isTinted) return Math.min(Math.max(reference * 2, harmonyMetrics.tintedLeast), harmonyMetrics.tintedMost);
    const least = this.isDark
      ? harmonyMetrics.darkLeast
      : lightness >= harmonyMetrics.pastel ? harmonyMetrics.pastelLeast : harmonyMetrics.lightLeast;
    return Math.min(Math.max(reference * 1.1, least), reference + harmonyMetrics.mostAbove);
  }

  /** `target` held near `lightness`, lifted clear of mud on a light gradient, and moved until the text reads over it. */
  private settle(target: number, lightness: number, reference: number, degrees: number) {
    const lightest = this.isAchromatic ? harmonyMetrics.lightestGray : harmonyMetrics.lightestColor;
    let settled = Math.min(
      Math.max(target, Math.max(harmonyMetrics.darkestGray, lightness - harmonyMetrics.farthestStep)),
      Math.min(lightest, lightness + harmonyMetrics.farthestStep),
    );
    const normalized = ((degrees % 360) + 360) % 360;
    if (!this.isDark && !this.isAchromatic && normalized >= harmonyMetrics.mudHues[0] && normalized <= harmonyMetrics.mudHues[1]) {
      settled = Math.max(settled, cuspLightness(degrees) - harmonyMetrics.mudLift);
    }
    let chroma = this.chroma(settled, degrees, reference);
    for (let nudges = 0; nudges < harmonyMetrics.textSteps && !this.readsText(settled, chroma, degrees); nudges++) {
      settled += this.isDark ? -harmonyMetrics.textNudge : harmonyMetrics.textNudge;
      chroma = this.chroma(settled, degrees, reference);
    }
    return { lightness: settled, chroma };
  }

  private chroma(lightness: number, degrees: number, reference: number): number {
    if (this.isAchromatic) return 0;
    const most = maximumChroma(clampUnit(lightness), (((degrees % 360) + 360) % 360) / 360);
    return Math.min(this.wantedChroma(lightness, reference), harmonyMetrics.gamutShare * most);
  }

  private readsText(lightness: number, chroma: number, degrees: number): boolean {
    const color = placedColor({ lightness, chroma, degrees, direction: 0 });
    return contrast(this.isDark ? 1 : 0, luminance(color)) >= this.textFloor;
  }
}

function shorterTurn(start: number, end: number): number {
  const turn = (end - start) % 360;
  return turn > 180 ? turn - 360 : turn <= -180 ? turn + 360 : turn;
}

/** CrestColorHarmony.run(beside:): the second and third colors Crest adds beside `base`, in order. */
export function harmonyRun(base: BrandColor): readonly [BrandColor, BrandColor] {
  const color = lch(base);
  const isAchromatic = color.chroma < harmonyMetrics.achromaticChroma;
  const harmony = new Harmony(base, isAchromatic, !isAchromatic && color.chroma < harmonyMetrics.tintedChroma);
  const lightness = clampUnit(color.lightness);
  const direction = harmony.isDark || lightness < harmonyMetrics.nearWhite ? 1 : -1;
  if (isAchromatic) {
    const second = harmony.place(lightness, 0, color.degrees, direction, harmonyMetrics.secondStep, true);
    const third = harmony.place(second.lightness, 0, color.degrees, second.direction, harmonyMetrics.thirdStep, false);
    return [placedColor(second), placedColor(third)];
  }
  const candidates = [1, -1].map((turn) => {
    const second = harmony.place(lightness, color.chroma, color.degrees + turn * harmonyMetrics.hueStep, direction,
      harmonyMetrics.secondStep, true);
    const reference = harmony.isTinted ? color.chroma : Math.max(color.chroma, second.chroma);
    const third = harmony.place(second.lightness, reference, color.degrees + 2 * turn * harmonyMetrics.hueStep,
      second.direction, harmonyMetrics.thirdStep, false);
    const score = second.chroma / harmony.wantedChroma(second.lightness, color.chroma)
      + 0.5 * third.chroma / harmony.wantedChroma(third.lightness, reference)
      - (isMuddy(placedLch(second)) ? 1 : 0) - (isMuddy(placedLch(third)) ? 1 : 0);
    return { score, colors: [placedColor(second), placedColor(third)] as const };
  });
  const [increasing, decreasing] = candidates;
  const tied = Math.abs(increasing.score - decreasing.score) < harmonyMetrics.tie;
  return tied || increasing.score >= decreasing.score ? increasing.colors : decreasing.colors;
}

/** CrestColorHarmony.third(after:_:): the color Crest adds after a person placed `first` and `second`. */
export function harmonyThird(first: BrandColor, second: BrandColor): BrandColor {
  const a = lch(first);
  const b = lch(second);
  const firstIsGray = a.chroma < harmonyMetrics.achromaticChroma;
  const secondIsGray = b.chroma < harmonyMetrics.achromaticChroma;
  if (firstIsGray && secondIsGray) {
    const step = b.lightness - a.lightness;
    const isDark = new Harmony(second, true, false).isDark;
    const lightness = Math.abs(step) > harmonyMetrics.flatStep
      ? b.lightness + step / 2
      : b.lightness + (isDark ? 1 : -1) * harmonyMetrics.thirdStep;
    return fromLch(Math.min(Math.max(lightness, harmonyMetrics.darkestGray), harmonyMetrics.lightestGray), 0, b.degrees / 360);
  }
  if (secondIsGray) return harmonyRun(first)[0];
  const harmony = new Harmony(second, false, b.chroma < harmonyMetrics.tintedChroma);
  const turn = firstIsGray ? harmonyMetrics.hueStep : shorterTurn(a.degrees, b.degrees);
  const sign = turn >= 0 ? 1 : -1;
  const width = Math.abs(turn) <= harmonyMetrics.contrastingTurn ? Math.min(Math.max(Math.abs(turn), 30), harmonyMetrics.hueStep) : 30;
  const lightnessStep = Math.min(Math.max(Math.abs(b.lightness - a.lightness) / 2, 0.04), 0.1);
  let earliest: Placed | null = null;
  for (const way of [sign, -sign]) {
    const placed = harmony.place(b.lightness, (a.chroma + b.chroma) / 2, b.degrees + way * width,
      b.lightness >= a.lightness ? 1 : -1, lightnessStep, false);
    if (!isMuddy(placedLch(placed))) return placedColor(placed);
    earliest ??= placed;
  }
  return earliest ? placedColor(earliest) : second;
}

// MARK: - Stops

/** CrestColorStopsMetrics.vibrancyRoom: what keeps a gray handle's partners from collapsing onto it as it moves out. */
const vibrancyRoom = 0.02;

/** CrestColorFill.maximumColors. */
export const maximumFillColors = 3;

/**
 * CrestColorStops: a fill's colors as the popover's handles. Each has an
 * identity, so a handle pops in and out as its color comes and goes; Crest
 * remembers which colors it placed and the person hasn't moved, so another
 * Add re-runs its harmony; and while linked, moving one color orbits the
 * rest rigidly with it from the shape they had when the move began.
 */
export class ColorStops {
  private identities: number[] = [];
  private placed = new Set<number>();
  private shape: WheelPoint[] | null = null;
  private nextIdentity = 1;

  /** The handles' identities for `fill`'s colors. */
  ids(fill: SpaceFill): readonly number[] {
    if (this.identities.length !== fill.colors.length) return fill.colors.map((_, index) => -1 - index);
    return this.identities;
  }

  adopt(fill: SpaceFill) {
    if (this.identities.length === fill.colors.length) return;
    this.identities = fill.colors.map(() => this.nextIdentity++);
    this.placed = new Set();
  }

  releaseShape() {
    this.shape = null;
  }

  /** `fill` with a color added where its harmony puts it. */
  add(fill: SpaceFill): SpaceFill {
    const first = fill.colors[0];
    if (fill.colors.length >= maximumFillColors || !first) return fill;
    this.adopt(fill);
    this.shape = null;
    let colors: BrandColor[];
    if (fill.colors.length === 1) {
      colors = [first, harmonyRun(first)[0]];
    } else if (this.placed.has(1)) {
      const run = harmonyRun(first);
      colors = [first, run[0], run[1]];
    } else {
      colors = [...fill.colors, harmonyThird(first, fill.colors[1])];
    }
    this.identities.push(this.nextIdentity++);
    this.placed.add(colors.length - 1);
    return { ...fill, colors };
  }

  /** `fill` without its color at `index`. */
  remove(index: number, fill: SpaceFill): SpaceFill {
    if (fill.colors.length <= 1 || index < 0 || index >= fill.colors.length) return fill;
    this.adopt(fill);
    this.shape = null;
    this.identities.splice(index, 1);
    this.placed = new Set([...this.placed].filter((at) => at !== index).map((at) => (at > index ? at - 1 : at)));
    return { ...fill, colors: fill.colors.filter((_, at) => at !== index) };
  }

  /** `fill` with `color` at `index`, the rest orbiting with it while `linked`. */
  move(color: BrandColor, index: number, fill: SpaceFill, linked: boolean): SpaceFill {
    if (!linked || fill.colors.length < 2 || index < 0 || index >= fill.colors.length) return this.set(color, index, fill);
    this.adopt(fill);
    if (this.shape?.length !== fill.colors.length) this.shape = fill.colors.map(readWheel);
    const shape = this.shape;
    const from = shape[index];
    const to = readWheel(color);
    const reach = (to.vibrancy + vibrancyRoom) / (from.vibrancy + vibrancyRoom);
    const colors = shape.map((stop, position) => (position === index
      ? color
      : wheelColor(wheelPoint(
        stop.hue + to.hue - from.hue,
        (stop.vibrancy + vibrancyRoom) * reach - vibrancyRoom,
        stop.lightness + to.lightness - from.lightness,
      ))));
    this.placed.delete(index);
    return { ...fill, colors };
  }

  private set(color: BrandColor, index: number, fill: SpaceFill): SpaceFill {
    if (index < 0 || index >= fill.colors.length) return fill;
    this.shape = null;
    this.placed.delete(index);
    return { ...fill, colors: fill.colors.map((existing, at) => (at === index ? color : existing)) };
  }
}
