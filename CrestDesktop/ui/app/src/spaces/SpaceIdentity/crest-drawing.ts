import {
  type CrestBackplate,
  CrestBackplateKinds,
  type CrestCharge,
  CrestChargeKind,
  CrestChargeKindKinds,
  type CrestChargeLayout,
  CrestChargeLayoutKinds,
  type CrestChargeWeight,
  CrestChargeWeightKinds,
  CrestDepthKinds,
  type CrestFieldDivision,
  CrestFieldDivisionKinds,
  CrestFinishKinds,
  CrestMonogramStyleKinds,
  type CrestOrdinary,
  CrestOrdinaryKinds,
  CrestSymbol,
  type CrestTrim,
  CrestTrimKinds,
  type SpaceBranding,
} from "@crest/contracts";

import { css } from "../../branding";
import { crestLayerFill, type FillDefinition, fillColorAt, fillPaint } from "../space-fills";

/**
 * What `SpaceCrestIcon` draws, worked out from the crest: each layer's paint
 * and the gradients they name, the plate's outline, and the shapes of the
 * band, trim and charge, which the component lays out as SVG.
 */
export interface CrestDrawing {
  /** The gradients the layers' paints name, in the order the layers first use them. */
  readonly definitions: readonly FillDefinition[];
  readonly plate: Rect;
  readonly plateSide: number;
  readonly plateD: string;
  readonly clip: string;
  readonly depth: string | undefined;
  readonly hasPlate: boolean;
  readonly layers: {
    readonly backplate: string;
    readonly secondary: string;
    readonly ordinary: string;
    readonly edge: string;
    readonly trim: string;
    readonly symbol: string;
  };
  readonly division: string;
  readonly finish: FinishShape | null;
  readonly ordinary: PathShape | null;
  readonly trim: readonly TrimShape[];
  /** The raised figure's shadow on its flat field, or nothing. */
  readonly figureDepth: string | undefined;
  readonly figures: readonly Figure[];
}

/** The plate's diameter as a fraction of the icon, before the crest's own plate scale. */
const plateFraction = 0.78;

/**
 * BrowserSpaceCrestIcon: plate, field, band, edge, trim and charge, composed
 * from paths and colored from the crest's own tinctures or the Space's.
 */
export function crestDrawing(branding: SpaceBranding, size: number, id: string): CrestDrawing {
  const crest = branding.crest;
  const plateSide = size * plateFraction * crest.plateScale;
  const plate: Rect = { x: (size - plateSide) / 2, y: (size - plateSide) / 2, width: plateSide, height: plateSide };
  // Each layer wears its palette entry's fill, one color or the gradient that
  // entry runs into across the plate, as the Mac's crestLayerFill.
  const definitions: FillDefinition[] = [];
  const paints = new Map<number, string>();
  const color = (index: number) => {
    const entry = Math.max(0, index);
    let paint = paints.get(entry);
    if (paint === undefined) {
      const painted = fillPaint(crestLayerFill(branding, entry), `crest-${id}-fill-${entry}`, plate);
      if (painted.definition) definitions.push(painted.definition);
      paint = painted.paint;
      paints.set(entry, paint);
    }
    return paint;
  };
  const layers = {
    backplate: color(crest.backplateColorIndex),
    secondary: color(crest.secondaryFieldColorIndex),
    ordinary: color(crest.ordinaryColorIndex),
    edge: color(crest.edgeColorIndex),
    trim: color(crest.trimColorIndex),
    symbol: color(crest.symbolColorIndex),
  };
  // A figure drawn as a symbol takes one color: the middle of its fill.
  const symbolColor = css(fillColorAt(crestLayerFill(branding, Math.max(0, crest.symbolColorIndex)), 0.5));
  const plateD = platePath(crest.backplate, plate, crest.sealTeeth);
  const depth = crest.depth.kind === CrestDepthKinds.Soft
    ? `drop-shadow(0 ${size * 0.02}px ${size * 0.04}px rgb(0 0 0 / 0.28))`
    : crest.depth.kind === CrestDepthKinds.Lifted
      ? `drop-shadow(0 ${size * 0.06}px ${size * 0.1}px rgb(0 0 0 / 0.36))`
      : undefined;
  return {
    definitions,
    plate,
    plateSide,
    plateD,
    clip: `crest-plate-${id}`,
    depth,
    hasPlate: crest.backplate.kind !== CrestBackplateKinds.None,
    layers,
    division: divisionPath(crest.fieldDivision, crest.divisionCount, plate),
    finish: finishShape(crest.finish.kind, crest.sheenAngle, plate, id),
    ordinary: ordinaryShape(crest.ordinary, crest.ordinaryWidth, plate, plateD, layers.ordinary),
    trim: trimShapes(crest.trim, crest.trimWeight, crest.trimDetail, crest.backplate, plate, layers.trim, size),
    // A raised figure casts the kit's paper shadow on its flat field, as BrowserSpaceCrestFigureDepth: 1.6 down, blurred 2.2, on the 64 grid.
    figureDepth: crest.depth.kind === CrestDepthKinds.Figure
      ? `drop-shadow(0 ${f((size * 1.6) / 64)}px ${f((size * 2.2) / 64)}px rgb(23 34 56 / 0.38))` : undefined,
    figures: chargeFigures({
      charge: crest.charge ?? { kind: CrestChargeKind.heraldic, symbol: crest.symbol, text: null, style: null },
      layout: crest.chargeLayout, scale: crest.chargeScale, offset: crest.chargeOffset, weight: crest.chargeWeight,
      paint: layers.symbol, solid: symbolColor, size, id,
    }),
  };
}

export interface Rect { readonly x: number; readonly y: number; readonly width: number; readonly height: number }

/** A path as the crest strokes or fills it. */
export interface PathShape {
  readonly d: string;
  readonly fill: string;
  readonly stroke?: string;
  readonly strokeWidth?: number;
  readonly strokeLinecap?: "butt";
  readonly strokeLinejoin?: "miter" | "round";
  readonly strokeMiterlimit?: number;
}

const f = (value: number) => Number(value.toFixed(3));

function ellipse(rect: Rect): string {
  const rx = rect.width / 2;
  const ry = rect.height / 2;
  const cx = rect.x + rx;
  const cy = rect.y + ry;
  return `M${f(cx - rx)} ${f(cy)}A${f(rx)} ${f(ry)} 0 1 0 ${f(cx + rx)} ${f(cy)}A${f(rx)} ${f(ry)} 0 1 0 ${f(cx - rx)} ${f(cy)}Z`;
}

function polygon(sides: number, rect: Rect, rotation: number): string {
  const cx = rect.x + rect.width / 2;
  const cy = rect.y + rect.height / 2;
  const radius = Math.min(rect.width, rect.height) / 2;
  let d = "";
  for (let index = 0; index < sides; index++) {
    const angle = rotation + (index / sides) * 2 * Math.PI;
    d += `${index === 0 ? "M" : "L"}${f(cx + Math.cos(angle) * radius)} ${f(cy + Math.sin(angle) * radius)}`;
  }
  return `${d}Z`;
}

function scalloped(rect: Rect, scallops: number): string {
  const cx = rect.x + rect.width / 2;
  const cy = rect.y + rect.height / 2;
  const outer = Math.min(rect.width, rect.height) / 2;
  const inner = outer * 0.9;
  let d = "";
  for (let index = 0; index < scallops; index++) {
    const start = (index / scallops) * 2 * Math.PI - Math.PI / 2;
    const end = ((index + 1) / scallops) * 2 * Math.PI - Math.PI / 2;
    const mid = (start + end) / 2;
    if (index === 0) d += `M${f(cx + Math.cos(start) * inner)} ${f(cy + Math.sin(start) * inner)}`;
    d += `Q${f(cx + Math.cos(mid) * outer * 1.08)} ${f(cy + Math.sin(mid) * outer * 1.08)} ${f(cx + Math.cos(end) * inner)} ${f(cy + Math.sin(end) * inner)}`;
  }
  return `${d}Z`;
}

/**
 * The simple vocabulary's soft shapes, as Crest's brand kit draws them on its
 * 64-unit grid, where a crest's plate spans 7 to 57.
 */
const kitOutlines: Partial<Record<CrestBackplateKinds, string>> = {
  [CrestBackplateKinds.SoftShield]: "M16 12H48Q52 12 52 16V31C52 44 43 51 32 55C21 51 12 44 12 31V16Q12 12 16 12Z",
  [CrestBackplateKinds.SoftHexagon]: "M27.67 11.49Q32 9 36.33 11.49L47.67 18.01Q52 20.5 52 25.5L52 38.5Q52 43.5 47.67 45.99L36.33 52.51"
    + "Q32 55 27.67 52.51L16.33 45.99Q12 43.5 12 38.5L12 25.5Q12 20.5 16.33 18.01Z",
  [CrestBackplateKinds.Ribbon]: "M14 15Q14 10 19 10L45 10Q50 10 50 15L50 49Q50 54 45.63 51.57L36.37 46.43Q32 44 27.63 46.43L18.37 51.57"
    + "Q14 54 14 49Z",
};

/** BrowserSpaceCrestKitOutline: a kit outline mapped from its grid, where the plate spans 7 to 57, onto `rect`. */
function kitPath(outline: string | undefined, rect: Rect): string {
  if (!outline) return ellipse(rect);
  const x = (value: number) => f(rect.x + ((value - 7) / 50) * rect.width);
  const y = (value: number) => f(rect.y + ((value - 7) / 50) * rect.height);
  return outline.replace(/([MLQCHVZ])([^MLQCHVZ]*)/g, (_, command: string, body: string) => {
    const numbers = body.trim() ? body.trim().split(/[\s,]+/).map(Number) : [];
    if (command === "H") return `H${numbers.map(x).join(" ")}`;
    if (command === "V") return `V${numbers.map(y).join(" ")}`;
    return command + numbers.map((value, index) => (index % 2 === 0 ? x(value) : y(value))).join(" ");
  });
}

/** BrowserSpaceCrestPlateShape: the plate's outline in `rect`. */
function platePath(backplate: CrestBackplate, rect: Rect, scallops = 14): string {
  const p = (x: number, y: number) => `${f(rect.x + x * rect.width)} ${f(rect.y + y * rect.height)}`;
  const { width: w, height: h } = rect;
  switch (backplate.kind) {
    case CrestBackplateKinds.None: return "";
    case CrestBackplateKinds.Circle: return ellipse(rect);
    case CrestBackplateKinds.Oval: return ellipse({ x: rect.x + w * 0.11, y: rect.y, width: w - w * 0.22, height: h });
    case CrestBackplateKinds.Shield:
      return `M${p(0.06, 0.08)}L${p(0.94, 0.08)}L${p(0.94, 0.46)}Q${p(0.94, 0.86)} ${p(0.5, 0.98)}Q${p(0.06, 0.86)} ${p(0.06, 0.46)}Z`;
    case CrestBackplateKinds.FrenchShield:
      return `M${p(0.08, 0.04)}L${p(0.92, 0.04)}L${p(0.92, 0.7)}Q${p(0.92, 0.97)} ${p(0.5, 0.97)}Q${p(0.08, 0.97)} ${p(0.08, 0.7)}Z`;
    case CrestBackplateKinds.Diamond: return `M${p(0.5, 0.02)}L${p(0.96, 0.5)}L${p(0.5, 0.98)}L${p(0.04, 0.5)}Z`;
    case CrestBackplateKinds.Hexagon: return polygon(6, rect, -Math.PI / 2);
    case CrestBackplateKinds.Octagon: return polygon(8, rect, Math.PI / 8);
    case CrestBackplateKinds.RoundedSquare: {
      const inset = { x: rect.x + w * 0.05, y: rect.y + h * 0.05, width: w * 0.9, height: h * 0.9 };
      return roundedRect(inset, w * 0.22);
    }
    case CrestBackplateKinds.Seal: return scalloped(rect, Math.max(6, scallops));
    case CrestBackplateKinds.Banner: return `M${p(0.12, 0.04)}L${p(0.88, 0.04)}L${p(0.88, 0.76)}L${p(0.5, 0.97)}L${p(0.12, 0.76)}Z`;
    case CrestBackplateKinds.SoftShield:
    case CrestBackplateKinds.SoftHexagon:
    case CrestBackplateKinds.Ribbon:
      return kitPath(kitOutlines[backplate.kind], rect);
    case CrestBackplateKinds.Badge: {
      // An arc over the top from 160° round to 20°, then down to the point.
      const cx = rect.x + 0.5 * w;
      const cy = rect.y + 0.44 * h;
      const radius = w * 0.44;
      const at = (degrees: number) => `${f(cx + Math.cos((degrees * Math.PI) / 180) * radius)} ${f(cy + Math.sin((degrees * Math.PI) / 180) * radius)}`;
      return `M${at(160)}A${f(radius)} ${f(radius)} 0 1 1 ${at(20)}L${p(0.5, 0.98)}Z`;
    }
    default: return ellipse(rect);
  }
}

function roundedRect(rect: Rect, radius: number): string {
  const r = Math.min(radius, rect.width / 2, rect.height / 2);
  const { x, y, width: w, height: h } = rect;
  return `M${f(x + r)} ${f(y)}H${f(x + w - r)}A${f(r)} ${f(r)} 0 0 1 ${f(x + w)} ${f(y + r)}V${f(y + h - r)}A${f(r)} ${f(r)} 0 0 1 ${f(x + w - r)} ${f(y + h)}H${f(x + r)}A${f(r)} ${f(r)} 0 0 1 ${f(x)} ${f(y + h - r)}V${f(y + r)}A${f(r)} ${f(r)} 0 0 1 ${f(x + r)} ${f(y)}Z`;
}

/** BrowserSpaceCrestDivisionShape: the part of the field that takes the second color. */
function divisionPath(division: CrestFieldDivision, count: number, rect: Rect): string {
  const p = (x: number, y: number) => `${f(rect.x + x * rect.width)} ${f(rect.y + y * rect.height)}`;
  const box = (x: number, y: number, width: number, height: number) => `M${f(x)} ${f(y)}h${f(width)}v${f(height)}h${f(-width)}Z`;
  const { x, y, width: w, height: h } = rect;
  switch (division.kind) {
    case CrestFieldDivisionKinds.Plain: return "";
    case CrestFieldDivisionKinds.PerPale: return box(x + w / 2, y, w / 2, h);
    case CrestFieldDivisionKinds.PerFess: return box(x, y + h / 2, w, h / 2);
    case CrestFieldDivisionKinds.PerBend: return `M${p(1, 0)}L${p(1, 1)}L${p(0, 1)}Z`;
    case CrestFieldDivisionKinds.PerChevron: return `M${p(0, 0.48)}L${p(0.5, 0.68)}L${p(1, 0.48)}L${p(1, 1)}L${p(0, 1)}Z`;
    case CrestFieldDivisionKinds.Quarterly: return box(x + w / 2, y, w / 2, h / 2) + box(x, y + h / 2, w / 2, h / 2);
    case CrestFieldDivisionKinds.PerSaltire: return `M${p(0, 0)}L${p(1, 0)}L${p(0.5, 0.5)}ZM${p(0, 1)}L${p(1, 1)}L${p(0.5, 0.5)}Z`;
    case CrestFieldDivisionKinds.Gyronny: {
      const wedges = Math.max(2, count) * 2;
      const cx = x + w / 2;
      const cy = y + h / 2;
      const radius = Math.max(w, h);
      let d = "";
      for (let index = 0; index < wedges; index += 2) {
        const start = (index / wedges) * 2 * Math.PI - Math.PI / 2;
        const end = ((index + 1) / wedges) * 2 * Math.PI - Math.PI / 2;
        d += `M${f(cx)} ${f(cy)}L${f(cx + Math.cos(start) * radius)} ${f(cy + Math.sin(start) * radius)}L${f(cx + Math.cos(end) * radius)} ${f(cy + Math.sin(end) * radius)}Z`;
      }
      return d;
    }
    case CrestFieldDivisionKinds.Barry: {
      const bands = Math.max(2, count);
      const band = h / bands;
      let d = "";
      for (let index = 1; index < bands; index += 2) d += box(x, y + index * band, w, band);
      return d;
    }
    case CrestFieldDivisionKinds.Paly: {
      const bands = Math.max(2, count);
      const band = w / bands;
      let d = "";
      for (let index = 1; index < bands; index += 2) d += box(x + index * band, y, band, h);
      return d;
    }
    case CrestFieldDivisionKinds.Checky: {
      const cells = Math.max(2, count);
      const cw = w / cells;
      const ch = h / cells;
      let d = "";
      for (let row = 0; row < cells; row++) {
        for (let column = 0; column < cells; column++) if ((row + column) % 2 === 1) d += box(x + column * cw, y + row * ch, cw, ch);
      }
      return d;
    }
    default: return "";
  }
}

/** The finish's gradient and the plate it covers. */
export interface FinishShape {
  readonly id: string;
  readonly start: { readonly x: number; readonly y: number };
  readonly end: { readonly x: number; readonly y: number };
  readonly stops: readonly (readonly [color: string, opacity: number, offset: number])[];
}

/** BrowserSpaceCrestField's finish: a sheen along the crest's angle, or an emboss from the top. */
function finishShape(kind: CrestFinishKinds, angle: number, plate: Rect, id: string): FinishShape | null {
  if (kind === CrestFinishKinds.Flat) return null;
  const gradient = `crest-finish-${id}`;
  const radians = (angle * Math.PI) / 180;
  const along = (direction: number) => ({
    x: plate.x + (0.5 + Math.cos(radians) * 0.5 * direction) * plate.width,
    y: plate.y + (0.5 + Math.sin(radians) * 0.5 * direction) * plate.height,
  });
  const [start, end] = kind === CrestFinishKinds.Sheen
    ? [along(-1), along(1)]
    : [{ x: plate.x + plate.width / 2, y: plate.y }, { x: plate.x + plate.width / 2, y: plate.y + plate.height }];
  const stops = kind === CrestFinishKinds.Sheen
    ? [["white", 0.34, 0], ["white", 0.06, 0.5], ["black", 0.1, 1]] as const
    : [["white", 0.22, 0], ["white", 0, 0.45], ["black", 0.26, 1]] as const;
  return { id: gradient, start, end, stops };
}

/** BrowserSpaceCrestOrdinaryPath and View: the band laid over the field, clipped to the plate. */
function ordinaryShape(ordinary: CrestOrdinary, width: number, plate: Rect, plateD: string, color: string): PathShape | null {
  const { x, y, width: w, height: h } = plate;
  const p = (u: number, v: number) => `${f(x + u * w)} ${f(y + v * h)}`;
  const band = Math.min(w, h) * 0.17 * width;
  const stroked = (d: string): PathShape => ({
    d, fill: "none", stroke: color, strokeWidth: band, strokeLinecap: "butt", strokeLinejoin: "miter", strokeMiterlimit: 10,
  });
  const filled = (d: string): PathShape => ({ d, fill: color });
  const box = (bx: number, by: number, bw: number, bh: number) => `M${f(bx)} ${f(by)}h${f(bw)}v${f(bh)}h${f(-bw)}Z`;
  switch (ordinary.kind) {
    case CrestOrdinaryKinds.None: return null;
    case CrestOrdinaryKinds.Pale: return filled(box(x + w / 2 - band / 2, y, band, h));
    case CrestOrdinaryKinds.Fess: return filled(box(x, y + h / 2 - band / 2, w, band));
    case CrestOrdinaryKinds.Bend: return stroked(`M${p(-0.1, -0.1)}L${p(1.1, 1.1)}`);
    case CrestOrdinaryKinds.Chevron: return stroked(`M${p(0.04, 0.78)}L${p(0.5, 0.34)}L${p(0.96, 0.78)}`);
    case CrestOrdinaryKinds.Cross: return filled(box(x + w / 2 - band / 2, y, band, h) + box(x, y + h / 2 - band / 2, w, band));
    case CrestOrdinaryKinds.Saltire: return stroked(`M${p(-0.1, -0.1)}L${p(1.1, 1.1)}M${p(1.1, -0.1)}L${p(-0.1, 1.1)}`);
    case CrestOrdinaryKinds.Chief: return filled(box(x, y, w, band * 1.4));
    case CrestOrdinaryKinds.Bordure:
      // The plate's own outline drawn inward: a stroke twice as wide, clipped to the plate.
      return { d: plateD, fill: "none", stroke: color, strokeWidth: plate.width * 0.09 * width * 2 };
    case CrestOrdinaryKinds.Pall: return stroked(`M${p(0.02, 0.02)}L${p(0.5, 0.5)}M${p(0.98, 0.02)}L${p(0.5, 0.5)}M${p(0.5, 0.5)}L${p(0.5, 1.02)}`);
    case CrestOrdinaryKinds.Pile: {
      const half = 0.28 * width;
      return filled(`M${p(0.5 - half, -0.02)}L${p(0.5 + half, -0.02)}L${p(0.5, 0.8)}Z`);
    }
    case CrestOrdinaryKinds.Canton: {
      const side = Math.min(w, h) * 0.36 * width;
      return filled(box(x, y, side, side));
    }
    case CrestOrdinaryKinds.Roundel: {
      const diameter = Math.min(w, h) * 0.34 * width;
      return filled(ellipse({ x: x + w / 2 - diameter / 2, y: y + h / 2 - diameter / 2, width: diameter, height: diameter }));
    }
    default: return null;
  }
}

/** One piece of the trim: a path, a laurel branch, or a ring of beads. */
export type TrimShape =
  | { readonly kind: "path"; readonly path: PathShape }
  | { readonly kind: "laurel"; readonly branch: LaurelBranch }
  | { readonly kind: "beads"; readonly fill: string; readonly beads: readonly { readonly cx: number; readonly cy: number; readonly r: number }[] };

/** BrowserSpaceCrestTrimView: what frames the plate. */
function trimShapes(trim: CrestTrim, weight: number, detail: number, backplate: CrestBackplate, plate: Rect, color: string,
  size: number): readonly TrimShape[] {
  const lineWidth = Math.max(0.75, size * 0.032 * weight);
  const scaled = (scale: number): Rect => {
    const width = plate.width * scale;
    const height = plate.height * scale;
    return { x: (size - width) / 2, y: (size - height) / 2, width, height };
  };
  const outline = (scale: number, width: number): TrimShape => ({
    kind: "path",
    path: { d: platePath(backplate, scaled(scale), 14), fill: "none", stroke: color, strokeWidth: width, strokeLinejoin: "round" },
  });
  switch (trim.kind) {
    case CrestTrimKinds.None: return [];
    case CrestTrimKinds.Shield: return [outline(1.12, lineWidth * 1.15)];
    case CrestTrimKinds.Line: return [outline(1.1, lineWidth * 0.8)];
    case CrestTrimKinds.DoubleLine:
    case CrestTrimKinds.DoubleRing:
      return [outline(1.09, lineWidth * 0.8), outline(1.2, lineWidth * 0.6)];
    case CrestTrimKinds.Seal:
      return [{ kind: "path", path: { d: scalloped(scaled(1.14), Math.max(8, detail)), fill: "none", stroke: color, strokeWidth: lineWidth * 0.8 } }];
    case CrestTrimKinds.Laurel: return laurel(size, weight, color).map((branch) => ({ kind: "laurel", branch }));
    case CrestTrimKinds.Sunburst: {
      const rays = Math.max(6, detail);
      const step = (2 * Math.PI) / rays;
      const spread = (step * Math.min(0.45, 0.35 * weight)) / 2;
      const c = size / 2;
      let d = "";
      for (let index = 0; index < rays; index++) {
        const angle = index * step - Math.PI / 2;
        const at = (a: number, r: number) => `${f(c + Math.cos(a) * size * r)} ${f(c + Math.sin(a) * size * r)}`;
        d += `M${at(angle - spread, 0.41)}L${at(angle, 0.5)}L${at(angle + spread, 0.41)}Z`;
      }
      return [{ kind: "path", path: { d, fill: color } }];
    }
    case CrestTrimKinds.Beaded: {
      const beads = Math.max(6, detail) * 2;
      const c = size / 2;
      const radius = size * 0.018 * weight;
      return [{
        kind: "beads",
        fill: color,
        beads: Array.from({ length: beads }, (_, index) => {
          const angle = (index / beads) * 2 * Math.PI - Math.PI / 2;
          return { cx: c + Math.cos(angle) * size * 0.455, cy: c + Math.sin(angle) * size * 0.455, r: radius };
        }),
      }];
    }
    default: return [];
  }
}

/** One side of the laurel: its stem, and the leaves along it. */
export interface LaurelBranch {
  readonly fill: string;
  readonly stem: PathShape;
  readonly leaves: readonly { readonly cx: number; readonly cy: number; readonly rx: number; readonly ry: number; readonly transform: string }[];
}

/**
 * The laurel trim, standing in for SF Symbols' laurel.leading and
 * laurel.trailing set half the icon tall with a quarter of it between them.
 */
function laurel(size: number, weight: number, color: string): readonly LaurelBranch[] {
  const height = size * 0.5;
  const gap = size * 0.26;
  const branch = (side: 1 | -1): LaurelBranch => {
    const stemX = size / 2 + side * (gap / 2 + height * 0.22);
    const top = (size - height) / 2;
    const leaves: LaurelBranch["leaves"][number][] = [];
    for (let index = 0; index < 5; index++) {
      const t = index / 4;
      const cx = stemX + side * Math.sin(t * Math.PI) * height * 0.08;
      const cy = top + height * (0.12 + t * 0.76);
      leaves.push({
        cx: cx - side * height * 0.08, cy, rx: height * 0.12, ry: height * 0.055, transform: `rotate(${side * (-35 + t * 20)} ${cx} ${cy})`,
      });
    }
    return {
      fill: color,
      stem: {
        d: `M${f(stemX)} ${f(top + height * 0.05)}Q${f(stemX + side * height * 0.12)} ${f(top + height * 0.55)} ${f(stemX)} ${f(top + height)}`,
        fill: "none",
        stroke: color,
        strokeWidth: Math.max(0.6, height * (weight > 1.3 ? 0.07 : 0.05)),
      },
      leaves,
    };
  };
  return [branch(-1), branch(1)];
}

/** The heraldic charges, Crest's own drawings shared with the Mac, by asset name. */
const heraldry: Record<string, string> = Object.fromEntries(
  Object.entries(import.meta.glob<string>("../../../../../../CrestShared/Resources/CrestHeraldry.xcassets/*/charge.svg", {
    eager: true,
    query: "?url",
    import: "default",
  })).map(([path, url]) => [path.split("/").at(-2)?.replace(/\.imageset$/, "") ?? "", url]),
);

/**
 * One figure as the crest draws it: a heraldic drawing masking its paint, a
 * symbol in one color, or letters or an emoji, at its place on the field.
 */
export type Figure =
  | { readonly kind: "drawing"; readonly x: number; readonly y: number; readonly side: number; readonly url: string; readonly mask: string; readonly tint: string }
  | { readonly kind: "symbol"; readonly x: number; readonly y: number; readonly size: number; readonly name: string; readonly stroke: number; readonly tint: string }
  | {
    readonly kind: "text";
    readonly x: number;
    readonly y: number;
    readonly text: string;
    readonly fontSize: number;
    readonly fontWeight?: number;
    readonly fill?: string;
    readonly fontFamily?: string;
  };

/** One figure's drawn box: its width and height. */
interface Glyph { readonly width: number; readonly height: number; readonly draw: (x: number, y: number, key: number) => Figure | null }

/** BrowserSpaceCrestChargeView: the figures arranged on the field. */
function chargeFigures({ charge, layout, scale, offset, weight, paint, solid, size, id }: {
  charge: CrestCharge;
  layout: CrestChargeLayout;
  scale: number;
  offset: number;
  weight: CrestChargeWeight;
  /** What the figure is filled with: a color, or a gradient's paint. */
  paint: string;
  /** The one color a figure drawn as a symbol wears. */
  solid: string;
  size: number;
  id: string;
}): readonly Figure[] {
  const glyph = (baseScale: number) => chargeGlyph(charge, size * baseScale * scale, weight, paint, solid, id);
  const c = size / 2;
  const dy = size * offset;
  const placed: (Figure | null)[] = [];
  const place = (g: Glyph, cx: number, cy: number) => placed.push(g.draw(cx - g.width / 2, cy - g.height / 2 + dy, placed.length));
  const row = (glyphs: readonly Glyph[], spacing: number, cy: number) => {
    const total = glyphs.reduce((sum, g) => sum + g.width, 0) + spacing * (glyphs.length - 1);
    let x = c - total / 2;
    for (const g of glyphs) {
      place(g, x + g.width / 2, cy);
      x += g.width + spacing;
    }
  };
  switch (layout.kind) {
    case CrestChargeLayoutKinds.Single: place(glyph(0.31), c, c); break;
    case CrestChargeLayoutKinds.Paired: row([glyph(0.22), glyph(0.22)], size * 0.07, c); break;
    case CrestChargeLayoutKinds.Trio: {
      const g = glyph(0.18);
      const spacing = -size * 0.03;
      const top = c - (g.height * 2 + spacing) / 2;
      row([g], 0, top + g.height / 2);
      row([g, g], size * 0.07, top + g.height + spacing + g.height / 2);
      break;
    }
    case CrestChargeLayoutKinds.Quad: {
      const g = glyph(0.17);
      const spacing = size * 0.02;
      const top = c - (g.height * 2 + spacing) / 2;
      row([g, g], size * 0.08, top + g.height / 2);
      row([g, g], size * 0.08, top + g.height + spacing + g.height / 2);
      break;
    }
    case CrestChargeLayoutKinds.Ring:
      for (let index = 0; index < 5; index++) {
        const angle = (index / 5) * 2 * Math.PI - Math.PI / 2;
        place(glyph(0.13), c + Math.cos(angle) * size * 0.2, c + Math.sin(angle) * size * 0.2);
      }
      break;
    default: place(glyph(0.31), c, c);
  }
  return placed.filter((figure): figure is Figure => figure !== null);
}

/** BrowserSpaceCrestChargeGlyph: one figure at `pointSize`, as the charge asks for it. */
function chargeGlyph(charge: CrestCharge, pointSize: number, weight: CrestChargeWeight, tint: string, solid: string, id: string): Glyph {
  const fontWeight = weight.kind === CrestChargeWeightKinds.Light ? 500 : weight.kind === CrestChargeWeightKinds.Regular ? 600 : 700;
  const stroke = weight.kind === CrestChargeWeightKinds.Light ? 1.75 : weight.kind === CrestChargeWeightKinds.Regular ? 2.1 : 2.5;
  switch (charge.kind.kind) {
    case CrestChargeKindKinds.Heraldic: {
      const symbol = charge.symbol ?? CrestSymbol.named("mountain") ?? null;
      const url = symbol?.assetName ? heraldry[symbol.assetName] : undefined;
      if (url) {
        const side = pointSize * 1.25;
        return {
          width: side,
          height: side,
          draw: (x, y, key) => ({ kind: "drawing", x, y, side, url, mask: `crest-charge-${id}-${key}`, tint }),
        };
      }
      return symbolGlyph(symbol?.systemImage ?? "shield.fill", pointSize, stroke, solid);
    }
    case CrestChargeKindKinds.System: return symbolGlyph(charge.text ?? "", pointSize, stroke, solid);
    case CrestChargeKindKinds.Emoji: {
      const fontSize = pointSize * 1.05;
      return textGlyph(charge.text ?? "", fontSize, fontSize * 1.25, fontSize * 1.2, {});
    }
    case CrestChargeKindKinds.Monogram: {
      const letters = charge.text ?? "";
      const count = [...letters].length;
      const fontSize = pointSize * (count > 1 ? 0.92 : 1.15);
      const serif = (charge.style?.kind ?? CrestMonogramStyleKinds.Serif) === CrestMonogramStyleKinds.Serif;
      return textGlyph(letters, fontSize, fontSize * 0.62 * Math.max(1, count), fontSize * 1.2, {
        fontWeight,
        fill: tint,
        fontFamily: serif ? "Georgia, 'Times New Roman', serif" : "'Segoe UI Variable Text', 'Segoe UI', sans-serif",
      });
    }
    default: return { width: 0, height: 0, draw: () => null };
  }
}

function symbolGlyph(name: string, pointSize: number, stroke: number, tint: string): Glyph {
  return {
    width: pointSize,
    height: pointSize,
    draw: (x, y) => ({ kind: "symbol", x, y, size: pointSize, name, stroke, tint }),
  };
}

function textGlyph(text: string, fontSize: number, width: number, height: number, style: {
  fontWeight?: number;
  fill?: string;
  fontFamily?: string;
}): Glyph {
  return {
    width,
    height,
    draw: (x, y) => ({ kind: "text", x: x + width / 2, y: y + height / 2, text, fontSize, ...style }),
  };
}
