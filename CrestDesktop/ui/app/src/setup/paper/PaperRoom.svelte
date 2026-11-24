<script lang="ts" module>
  import type { BrandColor } from "@crest/contracts";

  /** BrowserSetupPaperRoomMetrics.ground: parchment, or slate in the dark. */
  const ground = {
    light: { red: 0.965, green: 0.933, blue: 0.859, alpha: 1 },
    dark: { red: 0.169, green: 0.227, blue: 0.361, alpha: 1 },
  } satisfies Record<string, BrandColor>;
</script>

<script lang="ts">
  import { SpaceHouse, type SpaceBranding } from "@crest/contracts";
  import { motion as tokens } from "@crest/design";

  import { css } from "../../branding";
  import { presence } from "../../motion";
  import { backgroundFill, fillColorAt, mixOklab } from "../../spaces/space-fills";
  import { useReadsDark } from "./reads-dark";
  import TiledGrain from "./TiledGrain.svelte";

  /**
   * BrowserSetupPaperRoom: the room behind the preview, the shown Space's
   * Background drawn 35% of the way toward the ground in OKLab, toward its
   * angle, under a finer grain. It follows the Space the preview shows, Crest's
   * own look before there is one, each new look fading in over the last.
   */
  let { look, reducesMotion }: { look: SpaceBranding | null; reducesMotion: boolean } = $props();

  const background = $derived.by(() => {
    const fill = backgroundFill(look ?? SpaceHouse.crest.look);
    const toward = useReadsDark() ? ground.dark : ground.light;
    const mixed = { ...fill, colors: fill.colors.map((color) => mixOklab(color, toward, 0.35)) };
    const steps = mixed.colors.length < 2 ? [0] : Array.from({ length: 13 }, (_, step) => step / 12);
    const stops = steps.map((at) => `${css(fillColorAt(mixed, at))} ${Math.round(at * 100)}%`);
    return stops.length === 1 ? css(mixed.colors[0]) : `linear-gradient(${mixed.degrees + 90}deg, ${stops.join(", ")})`;
  });
  // Each look takes a layer above the one it replaces, which stays until the new one has come in.
  const layers = new Map<string, number>();
  const layer = (shown: string) => {
    if (!layers.has(shown)) layers.set(shown, layers.size + 1);
    return layers.get(shown);
  };
  const transition = $derived(reducesMotion ? { duration: 0 } : tokens.onboardingBackdropChange);
</script>

<span class="setup-room" aria-hidden="true">
  {#each [background] as shown (shown)}
    <span class="setup-room-layer" style:background={shown} style:z-index={layer(shown)}
      in:presence={{ pose: { opacity: 0 }, timing: transition }}
      out:presence={{ pose: { opacity: 1 }, timing: transition }}
    ></span>
  {/each}
  <TiledGrain density={1 / 60} opacity={0.45} />
</span>
