import type { BrandColor, SpaceBranding } from "@crest/contracts";
import { SpaceHouse } from "@crest/contracts";
import { useSyncExternalStore } from "react";

import { css } from "../branding";
import { grainSamples } from "../shell/SpaceBanner";
import { backgroundFill, fillColorAt, mixOklab } from "../spaces/space-fills";

/** Whether the device reads dark, which Setup's paper and room follow. */
export function useReadsDark(): boolean {
  return useSyncExternalStore(
    (listener) => {
      const query = matchMedia("(prefers-color-scheme: dark)");
      query.addEventListener("change", listener);
      return () => query.removeEventListener("change", listener);
    },
    () => matchMedia("(prefers-color-scheme: dark)").matches,
  );
}

/** CrestGrainTile's side: the grain repeats every 512 points, however large what it covers. */
const tileSide = 512;
const tiles = new Map<string, string>();

/**
 * CrestGrainTile: the Mac's paper grain as one 512-point tile at `density`
 * specks a square point, drawn once for each density and scale and then
 * repeated, light and dark specks in turn from the same seed as the banner's,
 * wrapped at the tile's edges so the repeat shows no seam.
 */
function grainTile(density: number): string {
  const scale = window.devicePixelRatio || 1;
  const key = `${density}@${scale}`;
  const cached = tiles.get(key);
  if (cached) return cached;
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(tileSide * scale);
  canvas.height = Math.round(tileSide * scale);
  const context = canvas.getContext("2d")!;
  context.setTransform(scale, 0, 0, scale, 0, 0);
  const count = Math.min(grainSamples.length, Math.round(tileSide * tileSide * density));
  for (const [light, fill] of [[true, "rgb(255 255 255 / 0.46)"], [false, "rgb(0 0 0 / 0.38)"]] as const) {
    context.fillStyle = fill;
    context.beginPath();
    for (let index = light ? 0 : 1; index < count; index += 2) {
      const [x, y, diameter] = grainSamples[index];
      const radius = diameter / 2;
      for (const dx of [0, -tileSide, tileSide]) {
        for (const dy of [0, -tileSide, tileSide]) {
          const cx = x * tileSide + dx;
          const cy = y * tileSide + dy;
          if (cx < -radius || cx > tileSide + radius || cy < -radius || cy > tileSide + radius) continue;
          context.moveTo(cx + radius, cy);
          context.arc(cx, cy, radius, 0, Math.PI * 2);
        }
      }
    }
    context.fill();
  }
  const url = canvas.toDataURL("image/png");
  tiles.set(key, url);
  return url;
}

/** Grain laid over what is behind it in soft light, as CrestGrain draws it. */
export function TiledGrain({ density, opacity }: { density: number; opacity: number }) {
  return (
    <span className="setup-grain" aria-hidden
      style={{ backgroundImage: `url(${grainTile(density)})`, backgroundSize: `${tileSide}px ${tileSide}px`, opacity }} />
  );
}

/** BrowserSetupPaper: the brand's canvas, cream or ink, under its grain. */
export function Paper() {
  return (
    <span className="setup-paper" aria-hidden>
      <TiledGrain density={1 / 24} opacity={0.35} />
    </span>
  );
}

/** BrowserSetupPaperRoomMetrics.ground: parchment, or slate in the dark. */
const ground = {
  light: { red: 0.965, green: 0.933, blue: 0.859, alpha: 1 },
  dark: { red: 0.169, green: 0.227, blue: 0.361, alpha: 1 },
} satisfies Record<string, BrandColor>;

/**
 * BrowserSetupPaperRoom: the room behind the preview, the shown Space's
 * Background drawn 35% of the way toward the ground in OKLab, toward its
 * angle, under a finer grain. It follows the Space the preview shows, Crest's
 * own look before there is one.
 */
export function PaperRoom({ look }: { look: SpaceBranding | null }) {
  const dark = useReadsDark();
  const fill = backgroundFill(look ?? SpaceHouse.crest.look);
  const toward = dark ? ground.dark : ground.light;
  const mixed = { ...fill, colors: fill.colors.map((color) => mixOklab(color, toward, 0.35)) };
  const steps = mixed.colors.length < 2 ? [0] : Array.from({ length: 13 }, (_, step) => step / 12);
  const stops = steps.map((at) => `${css(fillColorAt(mixed, at))} ${Math.round(at * 100)}%`);
  const background = stops.length === 1 ? css(mixed.colors[0]) : `linear-gradient(${mixed.degrees + 90}deg, ${stops.join(", ")})`;
  return (
    <span className="setup-room" aria-hidden style={{ background }}>
      <TiledGrain density={1 / 60} opacity={0.45} />
    </span>
  );
}

/** BrowserSetupSheetEdge: a 22-point band of shadow just past the sheet's edge, where it lies over the room. */
export function SheetEdge() {
  return <span className="setup-sheet-edge" aria-hidden />;
}
