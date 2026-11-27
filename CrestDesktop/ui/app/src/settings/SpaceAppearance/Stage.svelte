<script lang="ts">
  import type { SpaceBranding } from "@crest/contracts";

  import { BannerLayers } from "../../shell/SpaceBanner";
  import type { SpaceFill } from "../../spaces/space-fills";
  import { type CrestLayer, type CrestStep, crestLayers, layerFill, showsPattern } from "../../spaces/space-look";
  import { SpaceIdentityIcon } from "../../spaces/SpaceIdentity";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import FillDot from "./FillDot.svelte";
  import { colorName, sidebarRoles, sidebarTitles, wellFill, type WellRole } from "./space-appearance";

  /**
   * BrowserCrestForgeStage: the Space's icon at 188 on its own sidebar field,
   * shaded toward the trailing edge, its colors beside it, and while More
   * Customization shows a crest, the crest's parts' colors under them, with
   * Shuffle and Undo at the top. The stage reads dark whatever the Space.
   */
  let { branding, symbol, canUndo, onUndo, onShuffle, showsCrest, openWell, onWell, onStep }: {
    branding: SpaceBranding;
    symbol: string;
    canUndo: boolean;
    onUndo: () => void;
    onShuffle: () => void;
    showsCrest: boolean;
    openWell: WellRole | null;
    onWell: (role: WellRole, element: HTMLElement) => void;
    onStep: (step: CrestStep) => void;
  } = $props();

  let stage: HTMLDivElement | undefined = $state();
  let size = $state.raw({ width: 720, height: 284 });
  $effect(() => {
    const element = stage;
    if (!element) return;
    // The field fills the stage's whole box, its padding included.
    const observer = new ResizeObserver(() => (size = { width: element.offsetWidth, height: element.offsetHeight }));
    observer.observe(element);
    return () => observer.disconnect();
  });
</script>

<!-- BrowserCrestForgeSwatch: a 28-point circle of the fill over its title, which opens its color popover. -->
{#snippet swatch(title: string, fill: SpaceFill, selected: boolean, onToggle: (element: HTMLElement) => void)}
  {@const name = colorName(fill)}
  <button type="button" class={`forge-swatch${selected ? " selected" : ""}`} title={name === "Gradient" ? title : name}
    aria-label={title} {...{ "aria-description": name }} aria-expanded={selected}
    onclick={(event) => onToggle(event.currentTarget)}>
    <FillDot {fill} size={28} ring />
    <span class="forge-swatch-title">{title}</span>
  </button>
{/snippet}

<!--
  A crest part's swatch: its color, dimmed where the crest doesn't draw the
  part, when a press opens the step that adds it instead of a popover.
-->
{#snippet layerSwatch(layer: CrestLayer, selected: boolean, onToggle: (element: HTMLElement) => void)}
  {@const fill = layerFill(branding, layer)}
  {@const drawn = layer.draws(branding.crest)}
  {@const name = colorName(fill)}
  <button type="button" class={`forge-swatch${selected ? " selected" : ""}${drawn ? "" : " undrawn"}`}
    title={drawn ? (name === "Gradient" ? layer.title : name) : layer.hint} aria-label={layer.title}
    {...{ "aria-description": drawn ? name : layer.hint }}
    aria-expanded={drawn ? selected : undefined} onclick={(event) => onToggle(event.currentTarget)}>
    <FillDot {fill} size={28} ring />
    <span class="forge-swatch-title">{layer.title}</span>
  </button>
{/snippet}

<div bind:this={stage} class="forge-stage" data-testid="space-forge-stage">
  <div class="forge-stage-field" aria-hidden="true">
    <BannerLayers {branding} width={size.width} height={size.height} />
    <div class="forge-stage-shade"></div>
  </div>
  <div class="forge-stage-mark" aria-label="Crest preview" role="img">
    <SpaceIdentityIcon {symbol} {branding} size={188} />
  </div>
  <div class="forge-swatch-groups">
    <div class="forge-swatch-group">
      <h4>Colors</h4>
      <div class="forge-swatches">
        {#each sidebarRoles.filter((role) => role !== "pattern" || showsPattern(branding)) as role (role)}
          {@render swatch(sidebarTitles[role], wellFill(role, branding), openWell === role, (element) => onWell(role, element))}
        {/each}
      </div>
    </div>
    {#if showsCrest}
      <div class="forge-swatch-group">
        <h4>Crest</h4>
        <div class="forge-swatches">
          {#each crestLayers as layer (layer.slot)}
            {@render layerSwatch(layer, openWell === layer.slot,
              (element) => (layer.draws(branding.crest) ? onWell(layer.slot, element) : onStep(layer.step)))}
          {/each}
        </div>
      </div>
    {/if}
  </div>
  <div class="forge-tools">
    <button type="button" class="forge-tool" data-testid="space-forge-shuffle" onclick={onShuffle}>
      <SymbolIcon name="shuffle" size={12} strokeWidth={2} />
      <span>Shuffle</span>
    </button>
    <button type="button" class="forge-tool" disabled={!canUndo} data-testid="space-forge-undo" onclick={onUndo}>
      <SymbolIcon name="arrow.uturn.backward" size={12} strokeWidth={2} />
      <span>Undo</span>
    </button>
  </div>
</div>
