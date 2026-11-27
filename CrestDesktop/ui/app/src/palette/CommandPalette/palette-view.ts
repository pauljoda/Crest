import type { BrandColor, ShortcutBinding, TabState } from "@crest/contracts";

import { reader } from "../../reactive";
import type { PaletteModel } from "../palette-model";

/** BrowserCommandPaletteMetrics: the overlay card's sizes, in CSS pixels for the Mac's points. */
export const metrics = {
  maximumResultAreaHeight: 390,
  minimumResultAreaHeight: 82,
  reservedHeight: 117,
  fieldHeight: 68,
  cardPadding: 24,
  maximumCardWidth: 720,
} as const;

export interface PaletteProps {
  readonly model: PaletteModel;
  /** The keys each command answers to, for the badges command rows wear. */
  readonly bindings: readonly ShortcutBinding[];
  /** The Space's tabs, for the icons tab rows wear. */
  readonly tabs: readonly TabState[];
}

const versions = new WeakMap<PaletteModel, () => number>();

/**
 * The model's version, which follows each change it makes: read inside a
 * `$derived`, an `$effect` or a template expression, that expression runs
 * again after each, as the palette's views did when they rendered again.
 * An expression that reads the model reads this first.
 */
export function usePaletteVersion(model: PaletteModel): number {
  let read = versions.get(model);
  if (!read) {
    read = reader((listener) => model.subscribe(listener), () => model.version);
    versions.set(model, read);
  }
  return read();
}

export function brandColor(color: BrandColor): string {
  const channel = (value: number) => Math.round(Math.min(Math.max(value, 0), 1) * 255);
  return `rgb(${channel(color.red)} ${channel(color.green)} ${channel(color.blue)})`;
}
