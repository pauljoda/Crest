<script lang="ts" module>
  import type { SpaceCrest } from "@crest/contracts";

  /** One of a step's choices: the part, whether the crest wears it, and the crest made to wear it. */
  interface GalleryChoice {
    readonly name: string;
    readonly title: string;
    readonly selected: boolean;
    readonly apply: (crest: SpaceCrest) => SpaceCrest;
  }

  /** A step's gallery: each part `offered`, the one `worn` selected, applied to a crest by `apply`. */
  function gallery<T extends { readonly name: string; readonly title: string }>(offered: readonly T[], worn: T,
    apply: (crest: SpaceCrest, option: T) => SpaceCrest): readonly GalleryChoice[] {
    // A crest wearing a part no longer offered keeps it among the choices.
    const options = offered.some((option) => option.name === worn.name) ? offered : [...offered, worn];
    return options.map((option) => ({
      name: option.name,
      title: option.title,
      selected: option.name === worn.name,
      apply: (crest) => apply(crest, option),
    }));
  }
</script>

<script lang="ts">
  import { type SpaceBranding, SpaceIconStyle } from "@crest/contracts";

  import {
    applyingFinish,
    type CrestStep,
    crestSteps,
    finishChoices,
    offeredBackplates,
    offeredDivisions,
    offeredOrdinaries,
    offeredTrims,
    wearsFinish,
  } from "../../spaces/space-look";
  import { SpaceCrestIcon } from "../../spaces/SpaceIdentity";
  import { Segmented } from "../controls";
  import ChoiceTile from "./ChoiceTile.svelte";
  import CrestEmblem from "./CrestEmblem.svelte";
  import { rememberCrestStep, tileCrest } from "./crest-studio";

  /**
   * The Crest section under More Customization, for a crest icon: the
   * Mac's step bar, Shape, Field, Band, Emblem, Border and Finish, over the
   * step's gallery of crests wearing each choice, or for Emblem its source
   * and arrangement. `preview` is the look galleries draw from, the drag's
   * start while one runs; `defaults` the starting look the resets go back to.
   */
  let { branding, preview, defaults, step, onStep, write }: {
    branding: SpaceBranding;
    preview: SpaceBranding;
    defaults: SpaceBranding;
    step: CrestStep;
    onStep: (step: CrestStep) => void;
    write: (next: SpaceBranding) => void;
  } = $props();

  const crest = $derived(branding.crest);
  const writeCrest = (next: SpaceCrest) => write({ ...branding, crest: next, hasCustomAppearance: true });
  const look = (change: (crest: SpaceCrest) => SpaceCrest): SpaceBranding => ({
    ...preview,
    iconStyle: SpaceIconStyle.layeredCrest,
    crest: change(preview.crest),
  });
</script>

{#snippet galleryOf(choices: readonly GalleryChoice[])}
  <div class="forge-gallery" data-testid="space-forge-gallery">
    {#each choices as option (option.name)}
      <ChoiceTile title={option.title} selected={option.selected} onChoose={() => writeCrest(option.apply(crest))}>
        <SpaceCrestIcon branding={look(option.apply)} size={tileCrest} />
      </ChoiceTile>
    {/each}
  </div>
{/snippet}

<section class="settings-group" aria-label="Crest">
  <div class="settings-group-header forge-step-header">
    <h3>Crest</h3>
    <div data-testid="space-forge-steps">
      <Segmented label="Crest Studio step" value={step} choices={crestSteps.map(({ step: value, title }) => ({ value, label: title }))}
        onChange={(next: CrestStep) => {
          rememberCrestStep(next);
          onStep(next);
        }} />
    </div>
  </div>
  <div class="settings-card">
    {#if step === "shape"}
      {@render galleryOf(gallery(offeredBackplates, crest.backplate, (base, backplate) => ({ ...base, backplate })))}
    {:else if step === "field"}
      {@render galleryOf(gallery(offeredDivisions, crest.fieldDivision, (base, fieldDivision) => ({ ...base, fieldDivision })))}
    {:else if step === "band"}
      {@render galleryOf(gallery(offeredOrdinaries, crest.ordinary, (base, ordinary) => ({ ...base, ordinary })))}
    {:else if step === "border"}
      {@render galleryOf(gallery(offeredTrims, crest.trim, (base, trim) => ({ ...base, trim })))}
    {:else if step === "finish"}
      <div class="forge-gallery" data-testid="space-forge-gallery">
        {#each finishChoices as choice (choice.name)}
          <ChoiceTile title={choice.title} selected={wearsFinish(choice, crest)} onChoose={() => writeCrest(applyingFinish(choice, crest))}>
            <SpaceCrestIcon branding={look((base) => applyingFinish(choice, base))} size={tileCrest} />
          </ChoiceTile>
        {/each}
      </div>
    {:else if step === "emblem"}
      <CrestEmblem {branding} {preview} {defaults} {write} />
    {/if}
  </div>
</section>
