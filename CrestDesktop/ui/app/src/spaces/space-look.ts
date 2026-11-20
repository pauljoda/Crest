import {
  type BrandColor,
  type BrandGradient,
  type SpaceBannerPattern,
  SpaceBannerPattern as BannerPatterns,
  type SpaceBranding,
  SpaceGradientKind,
  type SpaceHouse,
  SpaceHouse as Houses,
  SpaceIconStyle,
  SpaceScheme,
  SpaceThemeMode,
  SpaceThemeModeKinds,
  Tincture,
} from "@crest/contracts";

import { accentFill, backgroundFill, type FillKind, shadedColor, slotFill, type SpaceFill } from "./space-fills";

/**
 * The Mac's SpaceBranding editing, as pure functions over the core's
 * branding: a Space's Background, Accent and Pattern written as fills, a
 * palette or a starter crest applied, and a sidebar pattern worn. Each
 * returns a whole new branding, which the core normalizes as it saves it
 * (SetSpaceBranding).
 */

const plainGradient: BrandGradient = { colors: { colors: [] }, kind: null, angle: 0 };

/** The kind a branding stores for a fill, where linear stores none. */
function storedKind(kind: FillKind) {
  return kind === "linear" ? null : SpaceGradientKind[kind];
}

/** The gradient a fill's colors after its first make, or none for one color. */
function gradientAfter(fill: SpaceFill): BrandGradient | null {
  return fill.colors.length > 1
    ? { colors: { colors: fill.colors.slice(1) }, kind: storedKind(fill.kind), angle: fill.degrees }
    : null;
}

/** `gradients` with `fill`'s gradient at `slot`, padded with plain slots; none when every slot is plain. */
function gradientsSetting(gradients: { readonly slots: readonly BrandGradient[] } | null, fill: SpaceFill, slot: number) {
  const slots = [...(gradients?.slots ?? [])];
  while (slots.length <= slot) slots.push(plainGradient);
  slots[slot] = gradientAfter(fill) ?? plainGradient;
  return slots.every((gradient) => gradient.colors.colors.length === 0) ? null : { slots };
}

/** The branding with `fill` at palette slot `slot`: its first color the slot's, the rest the slot's gradient. */
function withSlotFill(branding: SpaceBranding, fill: SpaceFill, slot: number): SpaceBranding {
  const color = fill.colors[0];
  const colors = [...branding.colors.colors];
  while (colors.length <= slot) colors.push(colors.at(-1) ?? color);
  colors[slot] = color;
  return {
    ...branding,
    colors: { colors },
    colorGradients: gradientsSetting(branding.colorGradients, fill, slot),
    hasCustomAppearance: true,
  };
}

/** A fill a tenth lighter, or darker where it is light, in each of its colors: a solid sidebar's pattern. */
export function shadedFill(fill: SpaceFill): SpaceFill {
  return { ...fill, colors: fill.colors.map(shadedColor) };
}

/**
 * SpaceBranding.backgroundFill's setter: the sidebar's Background, keeping
 * the Accent; a gradient theme turns into a solid banner, and a solid
 * sidebar's pattern follows as the Background's shade.
 */
export function withBackgroundFill(branding: SpaceBranding, fill: SpaceFill): SpaceBranding {
  const accent = accentFill(branding);
  let look = branding;
  if (look.themeMode.kind === SpaceThemeModeKinds.Gradient) {
    look = { ...look, themeMode: SpaceThemeMode.banner, bannerPattern: BannerPatterns.solid, colorGradients: null };
  }
  look = withSlotFill(look, fill, 0);
  look = withSlotFill(look, accent, 1);
  if (look.bannerPattern === BannerPatterns.solid) look = withSlotFill(look, shadedFill(fill), 2);
  return look;
}

/** SpaceBranding.accentFill's setter: the Accent, which takes back the icon's own color. */
export function withAccentFill(branding: SpaceBranding, fill: SpaceFill): SpaceBranding {
  return withSlotFill({ ...branding, symbolColor: null, symbolGradient: null }, fill, 1);
}

/** SpaceBranding.patternFill's setter: the color a patterned sidebar's shapes wear. */
export function withPatternFill(branding: SpaceBranding, fill: SpaceFill): SpaceBranding {
  return withSlotFill(branding, fill, 2);
}

/** SpaceBranding.followSpaceColors(): the crest gives up colors of its own and wears the Space's by role. */
export function followingSpaceColors(branding: SpaceBranding): SpaceBranding {
  return {
    ...branding,
    crest: {
      ...branding.crest,
      palette: null,
      paletteGradients: null,
      backplateColorIndex: 2,
      secondaryFieldColorIndex: 0,
      ordinaryColorIndex: 1,
      symbolColorIndex: 1,
      trimColorIndex: 1,
      edgeColorIndex: 0,
    },
    hasCustomAppearance: true,
  };
}

/** SpaceBranding.wearPattern(_:): the sidebar's pattern, a solid one wearing the Background's shade. */
export function wearingPattern(branding: SpaceBranding, pattern: SpaceBannerPattern): SpaceBranding {
  let look = branding.themeMode.kind === SpaceThemeModeKinds.Gradient ? withBackgroundFill(branding, backgroundFill(branding)) : branding;
  look = { ...look, bannerPattern: pattern };
  if (pattern === BannerPatterns.solid) look = withPatternFill(look, shadedFill(backgroundFill(look)));
  return { ...look, hasCustomAppearance: true };
}

/** Whether the sidebar shows a pattern the Pattern color paints. */
export function showsPattern(branding: SpaceBranding): boolean {
  return branding.themeMode.kind !== SpaceThemeModeKinds.Gradient && branding.bannerPattern !== BannerPatterns.solid;
}

/** The Pattern color's fill: palette slot 2. */
export function patternFill(branding: SpaceBranding): SpaceFill {
  return slotFill(branding, 2);
}

// MARK: - Palettes

/**
 * BrowserSpacePalette: a look a Space takes in one tap, a Background of
 * colors at one lightness turned a little round the wheel and an Accent
 * set well off it. Crest's own comes first, then light pastels, clear
 * brights and deep tones.
 */
export interface SpacePalette {
  readonly name: string;
  readonly title: string;
  readonly background: readonly BrandColor[];
  readonly accent: readonly BrandColor[];
  readonly degrees: number;
  readonly texture: number;
}

const rgb = (red: number, green: number, blue: number): BrandColor => ({ red, green, blue, alpha: 1 });

const palette = (name: string, title: string, background: readonly BrandColor[], accent: BrandColor, texture = 0, degrees = 90): SpacePalette =>
  ({ name, title, background, accent: [accent], degrees, texture });

export const spacePalettes: readonly SpacePalette[] = [
  palette("crest", "Crest", [Tincture.crestInk.color, Tincture.crestDusk.color, Tincture.crestSky.color], Tincture.crestButter.color, 0, 75),
  palette("blossom", "Blossom", [rgb(0.997, 0.814, 0.864), rgb(1, 0.846, 0.778)], rgb(0.779, 0.382, 0.455)),
  palette("lagoon", "Lagoon", [rgb(0.752, 0.929, 0.876), rgb(0.73, 0.904, 0.962)], rgb(0, 0.537, 0.628)),
  palette("lilac", "Lilac", [rgb(0.876, 0.831, 0.971), rgb(0.799, 0.876, 1)], rgb(0.504, 0.409, 0.747)),
  palette("linen", "Linen", [rgb(0.965, 0.899, 0.811), rgb(0.991, 0.866, 0.812)], rgb(0.749, 0.433, 0.244), 0.5),
  palette("sunset", "Sunset", [rgb(0.963, 0.533, 0.425), rgb(0.953, 0.682, 0.346)], rgb(1, 0.97, 0.922), 0.2),
  palette("ocean", "Ocean", [rgb(0.207, 0.609, 0.852), rgb(0.211, 0.729, 0.729)], rgb(0.874, 0.987, 0.992)),
  palette("orchid", "Orchid", [rgb(0.648, 0.39, 0.821), rgb(0.873, 0.415, 0.651)], rgb(1, 0.94, 0.992)),
  palette("citrus", "Citrus", [rgb(0.707, 0.86, 0.406), rgb(0.93, 0.853, 0.387)], rgb(0.205, 0.386, 0.164)),
  palette("midnight", "Midnight", [rgb(0.092, 0.152, 0.295), rgb(0.211, 0.169, 0.375)], rgb(0.705, 0.834, 0.971), 0.2),
  palette("forest", "Forest", [rgb(0.038, 0.215, 0.138), rgb(0, 0.268, 0.257)], rgb(0.727, 0.866, 0.696), 0.25),
  palette("ember", "Ember", [rgb(0.321, 0.083, 0.102), rgb(0.434, 0.104, 0.05)], rgb(0.954, 0.786, 0.595), 0.35),
  palette("plum", "Plum", [rgb(0.253, 0.102, 0.243), rgb(0.249, 0.168, 0.372)], rgb(0.923, 0.801, 0.908)),
];

export function paletteBackground(palette: SpacePalette): SpaceFill {
  return { colors: palette.background, kind: "linear", degrees: palette.degrees };
}

export function paletteAccent(palette: SpacePalette): SpaceFill {
  return { colors: palette.accent, kind: "linear", degrees: 90 };
}

const sameColors = (left: readonly BrandColor[], right: readonly BrandColor[]) => left.length === right.length
  && left.every((color, index) => Math.abs(color.red - right[index].red) <= 0.004
    && Math.abs(color.green - right[index].green) <= 0.004 && Math.abs(color.blue - right[index].blue) <= 0.004);

/** BrowserSpacePalette.isWorn: the Space's Background and Accent are the palette's colors. */
export function wearsPalette(palette: SpacePalette, branding: SpaceBranding): boolean {
  return sameColors(backgroundFill(branding).colors, palette.background) && sameColors(accentFill(branding).colors, palette.accent);
}

/** BrowserSpacePalette.applying(to:): the palette's colors and texture, the crest kept and following them. */
export function applyingPalette(palette: SpacePalette, branding: SpaceBranding): SpaceBranding {
  let look = followingSpaceColors(branding);
  look = withBackgroundFill(look, paletteBackground(palette));
  look = withAccentFill(look, paletteAccent(palette));
  return { ...look, textureStrength: palette.texture, hasCustomAppearance: true };
}

// MARK: - Starter crests

const sameCrest = (left: SpaceBranding["crest"], right: SpaceBranding["crest"]) =>
  JSON.stringify({ ...left, startingPresetId: null }) === JSON.stringify({ ...right, startingPresetId: null });

/** SpaceHouse.isWorn: the Space wears the house's own look, crest and all, untouched. */
export function wearsHouse(house: SpaceHouse, branding: SpaceBranding): boolean {
  const look = house.look;
  return branding.hasCustomAppearance !== true && branding.iconStyle === SpaceIconStyle.layeredCrest
    && JSON.stringify(branding.colors) === JSON.stringify(look.colors)
    && JSON.stringify(branding.colorGradients) === JSON.stringify(look.colorGradients)
    && branding.themeMode === look.themeMode
    && (look.themeMode.kind === SpaceThemeModeKinds.Gradient || branding.bannerPattern === look.bannerPattern)
    && sameCrest(branding.crest, look.crest);
}

/**
 * SpaceHouse.applying(to:): the house's colors, sidebar and crest; the
 * Space keeps its own strength, fade, folder colors and text unless it
 * started from a scheme.
 */
export function applyingHouse(house: SpaceHouse, branding: SpaceBranding): SpaceBranding {
  const look = house.look;
  const fromScheme = !!SpaceScheme.named(branding.crest.startingPresetId);
  return {
    ...branding,
    ...(fromScheme ? {
      bannerStrength: look.bannerStrength,
      readabilityFade: look.readabilityFade,
      textColorMode: look.textColorMode,
      symbolColor: look.symbolColor,
      symbolGradient: look.symbolGradient,
    } : {}),
    colors: look.colors,
    colorGradients: look.colorGradients,
    textureStrength: look.textureStrength,
    themeMode: look.themeMode,
    bannerPattern: look.bannerPattern,
    gradientAngle: look.gradientAngle,
    gradientKind: look.gradientKind,
    iconStyle: SpaceIconStyle.layeredCrest,
    crest: { ...look.crest, startingPresetId: house.name },
    hasCustomAppearance: false,
  };
}

/** The look a house shows on its tile: its own, as a crest. */
export function houseTileLook(house: SpaceHouse): SpaceBranding {
  return { ...house.look, iconStyle: SpaceIconStyle.layeredCrest };
}

/**
 * SpaceBranding.startingLook: the house or scheme the Space started from,
 * which Reset Appearance returns it to and each setting's reset reads.
 */
export function startingLook(branding: SpaceBranding): SpaceBranding | null {
  const preset = branding.crest.startingPresetId?.toLowerCase();
  if (!preset) return null;
  const house = Houses.all.find((candidate) => candidate.name.toLowerCase() === preset);
  if (house) return house.look;
  const scheme = SpaceScheme.all.find((candidate) => candidate.name.toLowerCase() === preset);
  if (!scheme) return null;
  const look = scheme.look;
  return {
    ...branding,
    colors: look.colors,
    colorGradients: look.colorGradients,
    themeMode: look.themeMode,
    bannerPattern: look.bannerPattern,
    gradientAngle: look.gradientAngle,
    gradientKind: look.gradientKind,
    bannerStrength: look.bannerStrength,
    readabilityFade: look.readabilityFade,
    textureStrength: look.textureStrength,
    textColorMode: look.textColorMode,
    iconStyle: look.iconStyle,
    symbolColor: look.symbolColor,
    symbolGradient: look.symbolGradient,
    crest: { ...branding.crest, startingPresetId: scheme.name },
    hasCustomAppearance: false,
  };
}
