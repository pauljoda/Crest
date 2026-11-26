/** CrestColorPopoverMetrics, CrestColorWheelMetrics and CrestColorSliderMetrics. */
export const metrics = {
  wheelHeight: 296,
  handle: 26,
  chosenHandle: 36,
  reach: 22,
  turnStep: 1 / 36,
  gridSpacing: 9,
  imageSize: 240,
  lightnessSteps: 64,
  trackSteps: 8,
  sliderThumb: 22,
  commitInterval: 33,
  slowestCommitInterval: 120,
  lateness: 8,
  paceStep: 8,
} as const;

/** How the handles move to their places: springing, as a pick or a press on the open wheel does, or at once under the pointer. */
export type Placing = "spring" | "instant";
