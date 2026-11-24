import type { CrestStep } from "../../spaces/space-look";

/** BrowserCrestForgeMetrics.tileCrestSize, and the Emblem grid's smaller crests. */
export const tileCrest = 56;
export const emblemCrest = 52;
/** How many emblems show before Browse all. */
export const firstEmblems = 12;

/** The step the studio shows, kept as the page moves between Spaces, as the Mac's tabState.forgeStep. */
let rememberedStep: CrestStep = "shape";

/** The step the studio opens on: the one last shown. */
export function initialCrestStep(): CrestStep {
  return rememberedStep;
}

/** Remembers a step the page opened, such as a crest swatch's. */
export function rememberCrestStep(step: CrestStep) {
  rememberedStep = step;
}
