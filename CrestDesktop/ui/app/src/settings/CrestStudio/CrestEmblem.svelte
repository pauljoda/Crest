<script lang="ts" module>
  import type { CrestCharge, CrestChargeLayout } from "@crest/contracts";

  import { offeredLayouts } from "../../spaces/space-look";

  const chargeKey = (charge: CrestCharge) => `${charge.kind.name}|${charge.symbol?.name ?? ""}|${charge.text ?? ""}|${charge.style?.name ?? ""}`;

  /** One, Two and Three, and the crest's own arrangement where it wears another. */
  function layoutChoices(worn: CrestChargeLayout): readonly CrestChargeLayout[] {
    return offeredLayouts.some((layout) => layout.name === worn.name) ? offeredLayouts : [...offeredLayouts, worn];
  }
</script>

<script lang="ts">
  import {
    CrestChargeKind,
    type CrestMonogramStyle,
    CrestMonogramStyle as MonogramStyles,
    type SpaceBranding,
    type SpaceCrest,
    SpaceIconStyle,
  } from "@crest/contracts";
  import { untrack } from "svelte";

  import { EmojiPicker, Popover } from "../../shell/pickers";
  import { resolvedCharge, selectableSymbols } from "../../spaces/space-look";
  import { SpaceCrestIcon } from "../../spaces/SpaceIdentity";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { Row, Segmented } from "../controls";
  import ChoiceTile from "./ChoiceTile.svelte";
  import { emblemCrest, firstEmblems } from "./crest-studio";
  import MenuRow from "./MenuRow.svelte";
  import SymbolPicker from "./SymbolPicker.svelte";

  /**
   * BrowserCrestStudioEmblem: the figure on the crest, from heraldry, a
   * symbol, an emoji or a monogram, or none, and how many of it. Each
   * source keeps what was last picked in it while the person tries others.
   */
  let { branding, preview, defaults, write }: {
    branding: SpaceBranding;
    preview: SpaceBranding;
    defaults: SpaceBranding;
    write: (next: SpaceBranding) => void;
  } = $props();

  const crest = $derived(branding.crest);
  const charge = $derived(resolvedCharge(crest));
  let source = $state.raw<CrestChargeKind>(untrack(() => resolvedCharge(branding.crest).kind));
  let systemName = $state("sparkles");
  let emoji = $state("🦁");
  let letters = $state("C");
  let letterStyle = $state.raw<CrestMonogramStyle>(MonogramStyles.serif);
  let search = $state("");
  let showsAll = $state(false);
  let picksEmoji = $state.raw<DOMRect | null>(null);
  let emojiButton: HTMLButtonElement | undefined = $state();
  const searchId = $props.id();

  // The source and its field follow the crest's figure, unless it has none.
  const key = $derived(chargeKey(charge));
  $effect(() => {
    key;
    untrack(() => {
      if (charge.kind.name === CrestChargeKind.none.name) return;
      source = charge.kind;
      if (charge.kind.name === CrestChargeKind.system.name) systemName = charge.text ?? "sparkles";
      else if (charge.kind.name === CrestChargeKind.emoji.name) emoji = charge.text ?? "🦁";
      else if (charge.kind.name === CrestChargeKind.monogram.name) {
        letters = charge.text ?? "C";
        letterStyle = charge.style ?? MonogramStyles.serif;
      }
    });
  });

  const writeCrest = (next: SpaceCrest) => write({ ...branding, crest: next, hasCustomAppearance: true });
  /** The figure `kind` makes from what was last picked in it. */
  const chargeOf = (kind: CrestChargeKind, fields: { system?: string; emoji?: string; letters?: string; style?: CrestMonogramStyle } = {}): CrestCharge => {
    switch (kind.name) {
      case CrestChargeKind.heraldic.name: return { kind, symbol: crest.symbol, text: null, style: null };
      case CrestChargeKind.system.name: return { kind, symbol: null, text: fields.system ?? systemName, style: null };
      case CrestChargeKind.emoji.name: return { kind, symbol: null, text: fields.emoji ?? emoji, style: null };
      case CrestChargeKind.monogram.name: return { kind, symbol: null, text: fields.letters ?? letters, style: fields.style ?? letterStyle };
      default: return { kind: CrestChargeKind.none, symbol: null, text: null, style: null };
    }
  };
  const choose = (kind: CrestChargeKind) => {
    source = kind;
    writeCrest({ ...crest, charge: chargeOf(kind) });
  };

  const words = $derived(search.trim().toLowerCase());
  const matching = $derived(words ? selectableSymbols.filter((symbol) => symbol.title.toLowerCase().includes(words)) : selectableSymbols);
  const shown = $derived(words || showsAll ? matching : matching.slice(0, firstEmblems));
  const defaultCharge = $derived(resolvedCharge(defaults.crest));
</script>

<div class="crest-emblem">
  <MenuRow title="Source" value={source.name} choices={CrestChargeKind.all.map((kind) => ({ value: kind.name, label: kind.title }))}
    onChange={(name) => choose(CrestChargeKind.named(name) ?? CrestChargeKind.none)}
    onReset={chargeKey(charge) !== chargeKey(defaultCharge) ? () => writeCrest({ ...crest, charge: defaults.crest.charge }) : null} />
  {#if source.name === CrestChargeKind.heraldic.name}
    <div class="crest-emblem-body">
      <label class="crest-emblem-search-title" for={searchId}>Find an emblem</label>
      <span class="settings-text-field">
        <SymbolIcon name="magnifyingglass" size={13} class="crest-emblem-search-glyph" />
        <input id={searchId} placeholder="Find an emblem" bind:value={search} />
      </span>
      {#if shown.length > 0}
        <div class="forge-gallery crest-emblem-grid">
          {#each shown as symbol (symbol.name)}
            <ChoiceTile title={symbol.title}
              selected={charge.kind.name === CrestChargeKind.heraldic.name && charge.symbol?.name === symbol.name}
              onChoose={() => writeCrest({ ...crest, symbol, charge: null })}>
              <SpaceCrestIcon branding={{ ...preview, iconStyle: SpaceIconStyle.layeredCrest, crest: { ...preview.crest, symbol, charge: null } }}
                size={emblemCrest} />
            </ChoiceTile>
          {/each}
        </div>
      {:else}
        <p class="crest-emblem-caption">No matching emblems. Try an SF Symbol or a monogram.</p>
      {/if}
      {#if !words && matching.length > firstEmblems}
        <button type="button" class="crest-emblem-more" onclick={() => (showsAll = !showsAll)}>
          {showsAll ? "Show fewer emblems" : `Browse all emblems (${matching.length})`}
        </button>
      {/if}
    </div>
  {/if}
  {#if source.name === CrestChargeKind.system.name}
    <div class="crest-emblem-body">
      <SymbolPicker inline current={charge.kind.name === CrestChargeKind.system.name ? charge.text ?? "" : ""}
        onChoose={(name) => {
          systemName = name;
          writeCrest({ ...crest, charge: chargeOf(CrestChargeKind.system, { system: name }) });
        }} />
    </div>
  {/if}
  {#if source.name === CrestChargeKind.emoji.name}
    <div class="crest-emblem-body">
      <button bind:this={emojiButton} type="button" class="forge-artwork-button" aria-label="Choose Emoji"
        {...{ "aria-description": emoji }}
        onclick={() => (picksEmoji = emojiButton?.getBoundingClientRect() ?? null)}>
        <span class="forge-artwork"><span class="forge-artwork-emoji">{emoji}</span></span>
        <span class="forge-artwork-text">
          <span class="forge-artwork-title">Emoji</span>
          <span class="forge-artwork-detail">Change emoji</span>
        </span>
        <SymbolIcon name="chevron.right" size={11} strokeWidth={2.5} />
      </button>
      {#each picksEmoji ? [picksEmoji] : [] as anchor ("emblem")}
        <Popover {anchor} label="Emblem" onClose={() => (picksEmoji = null)}>
          <EmojiPicker title="Emblem" current={emoji} resetTitle={null}
            onChoose={(chosen) => {
              emoji = chosen;
              writeCrest({ ...crest, charge: chargeOf(CrestChargeKind.emoji, { emoji: chosen }) });
              picksEmoji = null;
            }}
            onReset={() => (picksEmoji = null)} />
        </Popover>
      {/each}
    </div>
  {/if}
  {#if source.name === CrestChargeKind.monogram.name}
    <Row title="Letters">
      <span class="settings-text-field crest-monogram-field">
        <input aria-label="Letters" placeholder="One or two letters" value={letters} maxlength={2}
          oninput={(event) => {
            const typed = event.currentTarget.value;
            letters = typed;
            if (typed.trim()) writeCrest({ ...crest, charge: chargeOf(CrestChargeKind.monogram, { letters: typed }) });
          }} />
      </span>
    </Row>
    <Row title="Letter style">
      <Segmented label="Letter style" value={letterStyle.name}
        choices={MonogramStyles.all.map((style) => ({ value: style.name, label: style.title }))}
        onChange={(name) => {
          const style = MonogramStyles.all.find((each) => each.name === name) ?? MonogramStyles.serif;
          letterStyle = style;
          writeCrest({ ...crest, charge: chargeOf(CrestChargeKind.monogram, { style }) });
        }} />
    </Row>
  {/if}
  {#if source.name !== CrestChargeKind.none.name}
    <MenuRow title="Arrangement" value={crest.chargeLayout.name}
      choices={layoutChoices(crest.chargeLayout).map((layout) => ({ value: layout.name, label: layout.title }))}
      onChange={(name) => {
        const layout = layoutChoices(crest.chargeLayout).find((each) => each.name === name);
        if (layout) writeCrest({ ...crest, chargeLayout: layout });
      }}
      onReset={crest.chargeLayout.name !== defaults.crest.chargeLayout.name
        ? () => writeCrest({ ...crest, chargeLayout: defaults.crest.chargeLayout }) : null} />
  {/if}
</div>
