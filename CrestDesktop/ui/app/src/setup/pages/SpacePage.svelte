<script lang="ts" module>
  type Well = "background" | "accent";
  const wellTitles: Record<Well, string> = { background: "Background", accent: "Accent" };
  const wells = ["background", "accent"] as const;
</script>

<script lang="ts">
  import { type SpaceBranding, SpaceIconStyle } from "@crest/contracts";

  import type { Session } from "../../boot";
  import ColorPopoverContent from "../../settings/ColorPopover.svelte";
  import { Group, Row } from "../../settings/controls";
  import { ColorWell, IconPicker, PalettePicker } from "../../settings/SpaceAppearance";
  import { Popover } from "../../shell/pickers";
  import { accentFill, backgroundFill } from "../../spaces/space-fills";
  import { applyingHouse, withAccentFill, withBackgroundFill } from "../../spaces/space-look";
  import { useSetupSpace } from "../use-setup-space.svelte";

  /**
   * BrowserSetupSpacePage: a draft Space's name, its two colors and the
   * palettes, and its icon. Your Space edits the first Space; a Space's own
   * page under Spaces edits that one, titled with its name as it is typed.
   */
  let { session, spaceId, title }: { session: Session; spaceId: string | null; title: string | null } = $props();

  // svelte-ignore state_referenced_locally
  const setup = useSetupSpace(session, () => spaceId);
  const { space, customization, customize, error } = $derived(setup.current);
  let well = $state.raw<{ role: Well; anchor: DOMRect; element: HTMLElement } | null>(null);
  const flush: { current: (() => void) | null } = { current: null };
  const nameId = $props.id();

  const setBranding = (change: (look: SpaceBranding) => SpaceBranding) => customize((current) => ({ ...current, branding: change(current.branding) }));
  const closeWell = () => {
    flush.current?.();
    well = null;
  };
  const toggle = (role: Well, element: HTMLElement) => {
    if (well?.element === element) {
      closeWell();
      return;
    }
    if (well) closeWell();
    well = { role, anchor: element.getBoundingClientRect(), element };
  };
</script>

{#if !space || !customization}
  <div class="setup-page-content"><p class="setup-unavailable">No Space to Edit</p></div>
{:else}
  {@const branding = customization.branding}
  <div class="setup-page-content">
    <h2 class="setup-page-heading">{title ?? (customization.name.trim() || "Untitled Space")}</h2>
    <div class="settings-group">
      <div class="settings-card">
        <Row title="Name" htmlFor={nameId}>
          <input id={nameId} class="setup-name-field" data-testid="setup-space-name" value={customization.name} placeholder="Name"
            spellcheck={false} oninput={(event) => {
              const name = event.currentTarget.value;
              customize((current) => ({ ...current, name }));
            }} />
        </Row>
      </div>
    </div>
    <Group title="Colors">
      <div class="setup-wells" data-testid="space-color-wells">
        {#each wells as role (role)}
          <span class="setup-well">
            <ColorWell title={wellTitles[role]} fill={role === "background" ? backgroundFill(branding) : accentFill(branding)}
              selected={well?.role === role} onToggle={(element: HTMLElement) => toggle(role, element)} />
            <span class="setup-well-title">{wellTitles[role]}</span>
          </span>
        {/each}
      </div>
      <PalettePicker className="setup-palettes" {branding} onChoose={(next: SpaceBranding) => setBranding(() => next)} />
    </Group>
    <section class="settings-group">
      <div class="settings-group-header"><h3>Icon</h3></div>
      <IconPicker {branding} symbol={customization.symbol}
        onCrest={(house) => setBranding((look) => (house
          ? applyingHouse(house, look)
          : { ...look, iconStyle: SpaceIconStyle.layeredCrest, hasCustomAppearance: true }))}
        onWear={(symbol: string) => {
          // A symbol and the icon style it needs go in one change, which the core takes whole.
          customize((current) => ({
            ...current,
            symbol,
            branding: current.branding.iconStyle === SpaceIconStyle.simpleSymbol
              ? current.branding
              : { ...current.branding, iconStyle: SpaceIconStyle.simpleSymbol, hasCustomAppearance: true },
          }));
        }} />
    </section>
    {#if error}
      <p class="setup-error" role="alert">{error}</p>
    {/if}
    {#each well ? [well] : [] as shown (`${shown.role}-${shown.anchor.x}-${shown.anchor.y}`)}
      <Popover anchor={shown.anchor} label={wellTitles[shown.role]} edge="bottom" ignore={shown.element} className="color-popover"
        onClose={closeWell}>
        <ColorPopoverContent fill={shown.role === "background" ? backgroundFill(branding) : accentFill(branding)} {flush}
          onCommit={(fill) => setBranding((look) => (shown.role === "background" ? withBackgroundFill(look, fill) : withAccentFill(look, fill)))}
          texture={shown.role === "background"
            ? { value: branding.textureStrength, onChange: (textureStrength: number) => setBranding((look) => ({ ...look, textureStrength, hasCustomAppearance: true })) }
            : null} />
      </Popover>
    {/each}
  </div>
{/if}
