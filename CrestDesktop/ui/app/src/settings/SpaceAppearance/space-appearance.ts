import { type SpaceBranding, Tincture } from "@crest/contracts";

import { sameColor } from "../../spaces/color-harmony";
import { accentFill, backgroundFill, type SpaceFill } from "../../spaces/space-fills";
import {
  crestLayers,
  layerFill,
  patternFill,
  withAccentFill,
  withBackgroundFill,
  withLayerFill,
  withPatternFill,
} from "../../spaces/space-look";

/** BrowserCrestStudio's undo depth: the oldest look goes past it. */
export const historyLimit = 40;

/**
 * The colors a well edits: the Space's Background, its Accent, and the color
 * its sidebar pattern wears, or a part of its crest, by the layer's slot.
 */
export type WellRole = "background" | "accent" | "pattern" | number;

export const sidebarRoles = ["background", "accent", "pattern"] as const;
export const sidebarTitles = { background: "Background", accent: "Accent", pattern: "Pattern" } as const;

export const wellTitle = (role: WellRole) => (typeof role === "number" ? crestLayers[role].title : sidebarTitles[role]);

export function wellFill(role: WellRole, look: SpaceBranding): SpaceFill {
  if (typeof role === "number") return layerFill(look, crestLayers[role]);
  return role === "background" ? backgroundFill(look) : role === "accent" ? accentFill(look) : patternFill(look);
}

export function withWellFill(role: WellRole, look: SpaceBranding, fill: SpaceFill): SpaceBranding {
  if (typeof role === "number") return withLayerFill(look, crestLayers[role], fill);
  return role === "background" ? withBackgroundFill(look, fill) : role === "accent" ? withAccentFill(look, fill) : withPatternFill(look, fill);
}

export const sameLook = (left: SpaceBranding, right: SpaceBranding) => JSON.stringify(left) === JSON.stringify(right);

/** A fill's name: Gradient, the tincture its color is, or Custom. */
export function colorName(fill: SpaceFill): string {
  if (fill.colors.length > 1) return "Gradient";
  return Tincture.all.find((tincture) => sameColor(tincture.color, fill.colors[0]))?.title ?? "Custom";
}
