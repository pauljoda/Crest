<script lang="ts">
  import {
    type SpaceBannerPattern,
    SpaceBannerPattern as BannerPatterns,
    type SpaceBranding,
    SetSpaceBranding,
    SetSpaceIdentity,
    SpaceIconStyle,
    type SpaceState,
    SpaceTextColorMode,
    SpaceThemeModeKinds,
  } from "@crest/contracts";
  import { untrack } from "svelte";

  import type { Session } from "../../boot";
  import { Popover } from "../../shell/pickers";
  import { BannerLayers } from "../../shell/SpaceBanner";
  import {
    applyingHouse,
    crestFollowsSpace,
    type CrestStep,
    followingSpaceColors,
    patternFill,
    showsPattern,
    shuffledLook,
    startingLook,
    wearingPattern,
  } from "../../spaces/space-look";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import ColorPopoverContent from "../ColorPopover.svelte";
  import { Button, Group, Row, Segmented } from "../controls";
  import { ChoiceTile, CrestStudio, initialCrestStep, rememberCrestStep } from "../CrestStudio";
  import ColorWell from "./ColorWell.svelte";
  import IconPicker from "./IconPicker.svelte";
  import PalettePicker from "./PalettePicker.svelte";
  import SliderRow from "./SliderRow.svelte";
  import { historyLimit, sameLook, wellFill, type WellRole, wellTitle, withWellFill } from "./space-appearance";
  import Stage from "./Stage.svelte";

  /**
   * A Space's Appearance page, as the Mac's BrowserSpaceEditorView draws its
   * BrowserCrestForge: the Space's crest on its own sidebar field beside its
   * colors, with Undo; its palettes; its icon, a starter crest, a symbol or an
   * emoji; and More Customization, the sidebar's pattern, strength, fade,
   * folder colors, texture and text. Every change saves the whole look
   * (SetSpaceBranding), which the core normalizes; a symbol saves the Space's
   * identity (SetSpaceIdentity). The page is keyed by its Space, so its undo
   * history is the Space's own.
   */
  let { session, space }: { session: Session; space: SpaceState } = $props();

  // A drag's looks show at once and save as the core takes them; the page shows the drag's while it runs,
  // and its last until the core's look arrives.
  let draft = $state.raw<SpaceBranding | null>(null);
  const branding = $derived(draft ?? space.settings.look);
  let history = $state.raw<readonly SpaceBranding[]>([]);
  let showsMore = $state(false);
  let step = $state<CrestStep>(initialCrestStep());
  let dragStart = $state.raw<SpaceBranding | null>(null);
  let dragLatest: SpaceBranding | null = null;
  let pending: { branding: SpaceBranding; frame: number } | null = null;
  let well = $state.raw<{ role: WellRole; anchor: DOMRect; element: HTMLElement } | null>(null);
  const flushWell: { current: (() => void) | null } = { current: null };
  const defaults = untrack(() => startingLook(space.settings.look) ?? space.settings.look);

  const send = (next: SpaceBranding) => {
    void session.core.send(SetSpaceBranding({ workspaceId: session.workspaceId, spaceId: space.id, branding: next })).catch(() => {});
  };

  /** Saves `next`, one undo step from the look before it. */
  const write = (next: SpaceBranding) => {
    history = [...history, branding].slice(-historyLimit);
    send(next);
  };

  /**
   * A drag's look, `change` made to the drag's newest: shown at once, saved
   * at most once a frame, and one undo step for the whole drag. A color
   * popover's whole session is one drag.
   */
  const drag = (change: (look: SpaceBranding) => SpaceBranding) => {
    const next = change(dragLatest ?? branding);
    dragStart ??= branding;
    dragLatest = next;
    draft = next;
    if (pending) {
      pending.branding = next;
      return;
    }
    pending = {
      branding: next,
      frame: requestAnimationFrame(() => {
        const latest = pending?.branding;
        pending = null;
        if (latest) send(latest);
      }),
    };
  };
  const endDrag = () => {
    const start = dragStart;
    const latest = dragLatest;
    dragStart = null;
    dragLatest = null;
    if (!start) return;
    if (pending) {
      cancelAnimationFrame(pending.frame);
      send(pending.branding);
      pending = null;
    }
    if (!latest || !sameLook(start, latest)) history = [...history, start].slice(-historyLimit);
  };
  const spaceLook = $derived(space.settings.look);
  $effect(() => {
    spaceLook;
    untrack(() => {
      if (!dragStart) draft = null;
    });
  });
  $effect(() => () => {
    if (pending) cancelAnimationFrame(pending.frame);
  });

  const closeWell = () => {
    flushWell.current?.();
    well = null;
    endDrag();
  };
  /** Opens the popover for `role` under `element`, or closes it when it is that well's. */
  const toggleWell = (role: WellRole, element: HTMLElement) => {
    if (well?.element === element) {
      closeWell();
      return;
    }
    if (well) closeWell();
    well = { role, anchor: element.getBoundingClientRect(), element };
  };

  /** A crest swatch whose part the crest doesn't draw opens the step that adds it. */
  const openStep = (next: CrestStep) => {
    rememberCrestStep(next);
    step = next;
    showsMore = true;
  };

  const undo = () => {
    const previous = history.at(-1);
    if (!previous) return;
    history = history.slice(0, -1);
    send(previous);
  };

  /** A symbol or emoji for the Space's icon, which stops it drawing a crest. */
  const wear = (symbol: string) => {
    void session.core.send(SetSpaceIdentity({
      workspaceId: session.workspaceId, spaceId: space.id, name: space.settings.name, symbol, accent: space.settings.accent,
    })).catch(() => {});
    if (branding.iconStyle !== SpaceIconStyle.simpleSymbol) {
      write({ ...branding, iconStyle: SpaceIconStyle.simpleSymbol, hasCustomAppearance: true });
    }
  };
</script>

<!-- A sidebar pattern's tile: the Space's field wearing it, at 56 by 48. -->
{#snippet patternTile(pattern: SpaceBannerPattern, tileBranding: SpaceBranding, selected: boolean, onChoose: () => void)}
  <ChoiceTile title={pattern.title} {selected} {onChoose}>
    <span class="forge-pattern-art">
      <BannerLayers branding={wearingPattern(tileBranding, pattern)} width={56} height={48} />
    </span>
  </ChoiceTile>
{/snippet}

<div class="space-appearance" data-testid="space-customization-controls">
  <section class="space-appearance-section">
    <Stage {branding} symbol={space.settings.symbol} canUndo={history.length > 0} onUndo={undo}
      onShuffle={() => write(shuffledLook(branding))}
      showsCrest={showsMore && branding.iconStyle === SpaceIconStyle.layeredCrest}
      openWell={well?.element.closest(".forge-stage") ? well.role : null} onWell={toggleWell} onStep={openStep} />
    <PalettePicker className="settings-card" {branding} onChoose={write} />
  </section>

  <section class="space-appearance-section">
    <h3 class="forge-heading">Icon</h3>
    <IconPicker {branding} symbol={space.settings.symbol}
      onCrest={(house) => write(house ? applyingHouse(house, branding) : { ...branding, iconStyle: SpaceIconStyle.layeredCrest, hasCustomAppearance: true })}
      onWear={wear} />
  </section>

  <section class="space-appearance-section">
    <button type="button" class="settings-card forge-more" aria-expanded={showsMore} data-testid="more-customization"
      onclick={() => (showsMore = !showsMore)}>
      <span>More Customization</span>
      <SymbolIcon name="chevron.right" size={11} strokeWidth={2.5} class="forge-more-chevron" />
    </button>
  </section>

  {#if showsMore}
    <Group title="Sidebar">
      <div class="forge-gallery" data-testid="space-sidebar-patterns">
        {#each BannerPatterns.all as pattern (pattern.name)}
          {@render patternTile(pattern, dragStart ?? branding,
            branding.themeMode.kind === SpaceThemeModeKinds.Gradient ? pattern === BannerPatterns.solid : branding.bannerPattern === pattern,
            () => write(wearingPattern(branding, pattern)))}
        {/each}
      </div>
    </Group>
    <Group>
      {#if showsPattern(branding)}
        <Row title="Pattern color">
          <ColorWell title="Pattern color" fill={patternFill(branding)}
            selected={well?.role === "pattern" && !well.element.closest(".forge-stage")}
            onToggle={(element) => toggleWell("pattern", element)} />
        </Row>
      {/if}
      <SliderRow title="Intensity" value={branding.bannerStrength} defaultValue={defaults.bannerStrength}
        onDrag={(bannerStrength) => drag((look) => ({ ...look, bannerStrength, hasCustomAppearance: true }))} onEnd={endDrag}
        onReset={(bannerStrength) => write({ ...branding, bannerStrength, hasCustomAppearance: true })} />
      <SliderRow title="Readability fade" value={branding.readabilityFade} defaultValue={defaults.readabilityFade}
        onDrag={(readabilityFade) => drag((look) => ({ ...look, readabilityFade, hasCustomAppearance: true }))} onEnd={endDrag}
        onReset={(readabilityFade) => write({ ...branding, readabilityFade, hasCustomAppearance: true })} />
      <SliderRow title="Folder colors" value={branding.folderColorIntensity} defaultValue={defaults.folderColorIntensity}
        onDrag={(folderColorIntensity) => drag((look) => ({ ...look, folderColorIntensity, hasCustomAppearance: true }))} onEnd={endDrag}
        onReset={(folderColorIntensity) => write({ ...branding, folderColorIntensity, hasCustomAppearance: true })} />
      <SliderRow title="Texture" value={branding.textureStrength} defaultValue={defaults.textureStrength}
        readout={(value) => (value <= 0 ? "None" : value >= 1 ? "Full" : `${Math.round(value * 100)}%`)}
        onDrag={(textureStrength) => drag((look) => ({ ...look, textureStrength, hasCustomAppearance: true }))} onEnd={endDrag}
        onReset={(textureStrength) => write({ ...branding, textureStrength, hasCustomAppearance: true })} />
      <Row title="Text"
        onReset={branding.textColorMode !== defaults.textColorMode
          ? () => write({ ...branding, textColorMode: defaults.textColorMode, hasCustomAppearance: true }) : null}>
        <Segmented label="Text" value={branding.textColorMode}
          choices={SpaceTextColorMode.all.map((mode) => ({ value: mode, label: mode.title }))}
          onChange={(textColorMode) => write({ ...branding, textColorMode, hasCustomAppearance: true })} />
      </Row>
    </Group>
    {#if branding.iconStyle === SpaceIconStyle.layeredCrest}
      <CrestStudio {branding} preview={dragStart ?? branding} {defaults} {step} onStep={(next) => (step = next)} {write} />
      {#if !crestFollowsSpace(branding)}
        <Group>
          <Row title="The crest has colors of its own.">
            <Button onClick={() => write(followingSpaceColors(branding))}>Use Space Colors</Button>
          </Row>
        </Group>
      {/if}
    {/if}
  {/if}
  {#each well ? [well] : [] as shown (`${shown.role}-${shown.anchor.x}-${shown.anchor.y}`)}
    <Popover anchor={shown.anchor} label={wellTitle(shown.role)} edge="bottom" ignore={shown.element} className="color-popover"
      onClose={closeWell}>
      <ColorPopoverContent fill={wellFill(shown.role, branding)} flush={flushWell}
        onCommit={(fill) => drag((look) => withWellFill(shown.role, look, fill))}
        texture={shown.role === "background"
          ? { value: branding.textureStrength, onChange: (textureStrength) => drag((look) => ({ ...look, textureStrength, hasCustomAppearance: true })) }
          : null} />
    </Popover>
  {/each}
</div>
