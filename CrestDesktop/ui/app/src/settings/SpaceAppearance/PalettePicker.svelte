<script lang="ts">
  import type { SpaceBranding } from "@crest/contracts";

  import FillDefinition from "../../spaces/FillDefinition.svelte";
  import { fillPaint, type SpaceFill } from "../../spaces/space-fills";
  import { applyingPalette, paletteAccent, paletteBackground, spacePalettes, wearsPalette } from "../../spaces/space-look";
  import FillDot from "./FillDot.svelte";

  /** BrowserSpacePalettePicker: the palettes as cards, the one the Space wears selected; choosing one applies it. */
  let { branding, onChoose, className = "" }: {
    branding: SpaceBranding;
    onChoose: (next: SpaceBranding) => void;
    className?: string;
  } = $props();

  const uid = $props.id();
</script>

<!-- BrowserSpacePalettePicker's swatch: the Background across the tile, the Accent's dot where the icon sits. -->
{#snippet paletteSwatch(id: string, background: SpaceFill, accent: SpaceFill)}
  {@const painted = fillPaint(background, id, { x: 0, y: 0, width: 100, height: 24 })}
  <span class="space-palette-swatch">
    <svg width="100%" height="24" viewBox="0 0 100 24" preserveAspectRatio="none" aria-hidden="true">
      <defs>
        {#if painted.definition}<FillDefinition definition={painted.definition} />{/if}
      </defs>
      <rect width="100" height="24" fill={painted.paint} />
    </svg>
    <span class="space-palette-accent"><FillDot fill={accent} size={10} /></span>
  </span>
{/snippet}

<div class={`space-palettes ${className}`} role="group" aria-label="Palettes" data-testid="space-palettes">
  {#each spacePalettes as palette (palette.name)}
    {@const worn = wearsPalette(palette, branding)}
    <button type="button" class={`forge-card space-palette${worn ? " selected" : ""}`}
      aria-label={palette.title} aria-pressed={worn} title={palette.title} data-testid={`space-palette-${palette.name}`}
      onclick={() => onChoose(applyingPalette(palette, branding))}>
      {@render paletteSwatch(`palette-${uid}-${palette.name}`, paletteBackground(palette), paletteAccent(palette))}
      <span class="space-palette-title">{palette.title}</span>
    </button>
  {/each}
</div>
