import { type BrandColor, type SpaceBranding, SpaceTextColorMode, SpaceTextColorModeKinds } from "@crest/contracts";

import { darkSpaceDimming, useReadsDark } from "./appearance.svelte";
import { paintedColors } from "./spaces/space-fills";

/** The tone a Space's text reads in: light text, or dark. */
export type ForegroundTone = "light" | "dark";

/** BrandColor.indigo, the Mac's color for a palette with none. */
export const indigo: BrandColor = { red: 88 / 255, green: 86 / 255, blue: 214 / 255, alpha: 1 };

/** A brand color as CSS, at `opacity` times its own alpha. */
export function css(color: BrandColor, opacity = 1): string {
  const channel = (value: number) => Math.round(Math.min(1, Math.max(0, value)) * 255);
  return `rgb(${channel(color.red)} ${channel(color.green)} ${channel(color.blue)} / ${color.alpha * opacity})`;
}

/** `from` moved `fraction` of the way to `to`, as SwiftUI's `mix(with:by:)` and AppKit's blend do. */
export function mix(from: BrandColor, to: BrandColor, fraction: number): BrandColor {
  const along = (a: number, b: number) => a + (b - a) * fraction;
  return { red: along(from.red, to.red), green: along(from.green, to.green), blue: along(from.blue, to.blue), alpha: along(from.alpha, to.alpha) };
}

export const white: BrandColor = { red: 1, green: 1, blue: 1, alpha: 1 };
export const black: BrandColor = { red: 0, green: 0, blue: 0, alpha: 1 };

/**
 * The Space's colors by the part each plays in its sidebar, as the Mac's
 * BrowserSpaceBrandColorRole slots them: background, accent, pattern.
 */
export function backgroundColor(branding: SpaceBranding): BrandColor {
  return branding.colors.colors[0] ?? indigo;
}

export function primaryColor(branding: SpaceBranding): BrandColor {
  return branding.colors.colors[1] ?? backgroundColor(branding);
}

/** The icon's own color, or the Space's primary color when it has none. */
export function resolvedSymbolColor(branding: SpaceBranding): BrandColor {
  return branding.symbolColor ?? primaryColor(branding);
}

/** The window's displayed palette, following SpaceBranding.appearing(in:dimming:). */
export function displayedBranding(look: SpaceBranding): SpaceBranding {
  const amount = useReadsDark() ? darkSpaceDimming.current / 100 : 0;
  if (!amount) return look;
  const colors = look.colors.colors.map(color => {
    const high = Math.max(color.red, color.green, color.blue);
    const low = Math.min(color.red, color.green, color.blue);
    const brightness = Math.min(high, 0.08 + 0.04 * high);
    const saturation = high ? 0.8 * (high - low) / high : 0;
    const channel = (value: number) => {
      const distance = high > low ? (high - value) / (high - low) : 0;
      return value + (brightness * (1 - saturation * distance) - value) * amount;
    };
    return { red: channel(color.red), green: channel(color.green), blue: channel(color.blue), alpha: color.alpha };
  });
  return { ...look, colors: { colors }, readabilityFade: look.readabilityFade * (1 - amount), textColorMode: SpaceTextColorMode.automatic };
}

/** The tone the device's appearance reads in: light text over a dark window. */
export function systemTone(): ForegroundTone {
  return useReadsDark() ? "light" : "dark";
}

/**
 * The tone that reads best over the colors the Space's banner paints, unless
 * its text color mode names one or follows the device, as
 * SpaceBranding.foregroundTone(system:).
 */
export function foregroundTone(branding: SpaceBranding | null | undefined, system: ForegroundTone = systemTone()): ForegroundTone {
  if (!branding) return system;
  branding = displayedBranding(branding);
  switch (branding.textColorMode.kind) {
    case SpaceTextColorModeKinds.Light: return "light";
    case SpaceTextColorModeKinds.Dark: return "dark";
    case SpaceTextColorModeKinds.System: return system;
    default: break;
  }
  return paletteTone(paintedColors(branding), branding.bannerStrength, branding.readabilityFade, system);
}

/** The text tone that reads over `color` itself, as browserReadableForeground(over:) picks it. */
export function toneOver(color: BrandColor): ForegroundTone {
  return paletteTone([color], 1, 0, "dark");
}

/** Whether light text reads over the Space's banner. */
export function readsLight(branding: SpaceBranding | null | undefined): boolean {
  return foregroundTone(branding) === "light";
}

/**
 * ColorPalette.foregroundTone: each color as the sidebar draws it, at the
 * look's strength over the window's own background and under the readability
 * fade, and the text tone whose weakest APCA contrast across them is strongest.
 */
function paletteTone(colors: readonly BrandColor[], strength: number, readabilityFade: number, system: ForegroundTone): ForegroundTone {
  const window = system === "light" ? 0.12 : 0.93;
  const overlay = Math.min(readabilityFade * 0.55, 0.7);
  const rendered = (channel: number) => (channel * strength + window * (1 - strength)) * (1 - overlay);
  const backgrounds = colors.map((color) => screenLuminance(rendered(color.red), rendered(color.green), rendered(color.blue)));
  const lightText = screenLuminance(1, 1, 1);
  const darkText = screenLuminance(0, 0, 0);
  const light = Math.min(...backgrounds.map((background) => lightnessContrast(lightText, background)));
  const dark = Math.min(...backgrounds.map((background) => lightnessContrast(darkText, background)));
  return light >= dark ? "light" : "dark";
}

function screenLuminance(red: number, green: number, blue: number): number {
  const luminance = 0.2126729 * red ** 2.4 + 0.7151522 * green ** 2.4 + 0.072175 * blue ** 2.4;
  return luminance < 0.022 ? luminance + (0.022 - luminance) ** 1.414 : luminance;
}

function lightnessContrast(text: number, background: number): number {
  if (Math.abs(background - text) < 0.0005) return 0;
  if (background > text) {
    const contrast = (background ** 0.56 - text ** 0.57) * 1.14;
    return contrast < 0.1 ? 0 : (contrast - 0.027) * 100;
  }
  const contrast = (background ** 0.65 - text ** 0.62) * 1.14;
  return contrast > -0.1 ? 0 : -(contrast + 0.027) * 100;
}

/** The emoji a Space or tab symbol carries, if it is one rather than a symbol name. */
export function emojiOf(symbol: string): string | null {
  const prefix = "crest.emoji:";
  if (!symbol.startsWith(prefix)) return null;
  // The first character as a person sees it, which can be several code points.
  const [first] = new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(symbol.slice(prefix.length).trim());
  return first?.segment ?? null;
}
