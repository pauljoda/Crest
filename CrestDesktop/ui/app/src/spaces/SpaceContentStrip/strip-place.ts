/**
 * The Space whose place in the strip a card stands in, so it knows whether a
 * slide brings it or takes it away, and whether it waits, drawn unseen,
 * beside the shown Space for a slide to take it up.
 *
 * `StripPlace` is also the context's key: a card reads it with
 * `getContext<StripPlace | undefined>(StripPlace)`, undefined outside the
 * strip, and reads its fields inside reactive expressions, which then follow
 * the strip as it moves.
 */
export interface StripPlace {
  readonly id: string;
  readonly waits: boolean;
}

export const StripPlace = Symbol("StripPlace");
