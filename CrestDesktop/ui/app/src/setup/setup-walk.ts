/**
 * Setup's steps and the pages between them, as the Mac's BrowserSetupStep,
 * BrowserSetupWalk and BrowserSetupDestination: each step has a page, and
 * some have deeper pages, a Space's own under Spaces. The person walks the
 * steps in order; Continue goes to the next step's page, Back to the one
 * before, and the chips open any step the walk takes.
 */

import { brand } from "@crest/design";

export type SetupStepName = "bring" | "yourSpace" | "spaces" | "home";

export interface SetupStepInfo {
  readonly name: SetupStepName;
  readonly title: string;
  /** The chip's paper color, one of the mark's and the brand's. */
  readonly color: readonly [number, number, number];
}

export const setupSteps: Readonly<Record<SetupStepName, SetupStepInfo>> = {
  bring: { name: "bring", title: "Bring Tabs", color: brand.sky as readonly [number, number, number] },
  yourSpace: { name: "yourSpace", title: "Your Space", color: brand.coral as readonly [number, number, number] },
  spaces: { name: "spaces", title: "Spaces", color: [141, 191, 154] },
  home: { name: "home", title: "Make It Home", color: brand.butter as readonly [number, number, number] },
};

/** A page Setup shows: a step's own page, or a Space's under Spaces. */
export type SetupPage =
  | { readonly kind: "step"; readonly step: SetupStepName }
  | { readonly kind: "space"; readonly spaceId: string };

/** The step a page belongs to. */
export function stepOf(page: SetupPage): SetupStepName {
  return page.kind === "step" ? page.step : "spaces";
}

export const stepPage = (step: SetupStepName): SetupPage => ({ kind: "step", step });

export function samePage(left: SetupPage, right: SetupPage): boolean {
  return left.kind === right.kind && (left.kind === "step" ? left.step === (right as typeof left).step : left.spaceId === (right as typeof left).spaceId);
}

/**
 * The steps this Setup walks: Bring Tabs only where the platform reads other
 * browsers, and Your Space only when no browser's Spaces are coming in.
 */
export function setupWalk(offersBring: boolean, imports: boolean): readonly SetupStepName[] {
  if (imports) return ["bring", "spaces", "home"];
  return offersBring ? ["bring", "yourSpace", "spaces", "home"] : ["yourSpace", "spaces", "home"];
}

export function stepAfter(walk: readonly SetupStepName[], step: SetupStepName): SetupStepName | null {
  const index = walk.indexOf(step);
  return index >= 0 && index < walk.length - 1 ? walk[index + 1] : null;
}

export function stepBefore(walk: readonly SetupStepName[], step: SetupStepName): SetupStepName | null {
  const index = walk.indexOf(step);
  return index > 0 ? walk[index - 1] : null;
}
