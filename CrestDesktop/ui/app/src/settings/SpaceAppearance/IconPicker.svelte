<script lang="ts" module>
  type IconKind = "crest" | "symbol" | "emoji";
</script>

<script lang="ts">
  import { type SpaceBranding, SpaceHouse, SpaceHouseStyle, SpaceIconStyle } from "@crest/contracts";
  import { untrack } from "svelte";

  import { emojiOf } from "../../branding";
  import { EmojiPicker, Popover } from "../../shell/pickers";
  import { houseTileLook, wearsHouse } from "../../spaces/space-look";
  import { SpaceCrestIcon } from "../../spaces/SpaceIdentity";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { Segmented } from "../controls";
  import { ChoiceTile, SymbolPicker } from "../CrestStudio";

  /**
   * BrowserSpaceIconPicker: Crest, Symbol or Emoji. A crest offers the starter
   * houses, Simple then Heraldic, each in its own colors; a symbol and an
   * emoji each open a picker, and wear what is picked.
   */
  let { branding, symbol, onCrest, onWear }: {
    branding: SpaceBranding;
    symbol: string;
    onCrest: (house: SpaceHouse | null) => void;
    onWear: (symbol: string) => void;
  } = $props();

  const emoji = $derived(emojiOf(symbol));
  const worn: IconKind = $derived(branding.iconStyle === SpaceIconStyle.layeredCrest ? "crest" : emoji ? "emoji" : "symbol");
  // Choosing a first emoji shows the Emoji kind before anything is worn.
  let override = $state<IconKind | null>(null);
  const iconStyle = $derived(branding.iconStyle);
  $effect(() => {
    iconStyle;
    symbol;
    untrack(() => (override = null));
  });
  const kind = $derived(override ?? worn);
  let picking = $state.raw<{ kind: "symbol" | "emoji"; anchor: DOMRect } | null>(null);
  let button: HTMLButtonElement | undefined = $state();
  const open = (which: "symbol" | "emoji") => {
    const anchor = button?.getBoundingClientRect();
    if (anchor) picking = { kind: which, anchor };
  };
</script>

<div class="settings-card forge-icon">
  <div class="forge-icon-kind" data-testid="space-icon-kind">
    <Segmented label="Icon" value={kind}
      choices={[{ value: "crest", label: "Crest" }, { value: "symbol", label: "Symbol" }, { value: "emoji", label: "Emoji" }]}
      onChange={(next: IconKind) => {
        if (next === "crest") onCrest(null);
        else if (next === "symbol") onWear(emoji ? "sparkles" : symbol);
        else {
          override = "emoji";
          requestAnimationFrame(() => open("emoji"));
        }
      }} />
  </div>
  {#if kind === "crest"}
    <div class="forge-starters" data-testid="space-starter-crests">
      {#each SpaceHouseStyle.all as style (style.name)}
        <div class="forge-starter-group">
          <h4 class="forge-caps">{style.title}</h4>
          <div class="forge-gallery">
            {#each SpaceHouse.all.filter((house) => house.style === style) as house (house.name)}
              <ChoiceTile title={house.title} selected={wearsHouse(house, branding)} onChoose={() => onCrest(house)}>
                <SpaceCrestIcon branding={houseTileLook(house)} size={56} />
              </ChoiceTile>
            {/each}
          </div>
        </div>
      {/each}
    </div>
  {:else}
    <button bind:this={button} type="button" class="forge-artwork-button"
      aria-label={kind === "symbol" ? "Choose SF Symbol" : "Choose Emoji"} onclick={() => open(kind)}>
      <span class="forge-artwork">
        {#if kind === "emoji"}
          {#if emoji}<span class="forge-artwork-emoji">{emoji}</span>{:else}<SymbolIcon name="face.smiling" size={24} />{/if}
        {:else}
          <SymbolIcon name={symbol} size={24} />
        {/if}
      </span>
      <span class="forge-artwork-text">
        <span class="forge-artwork-title">{kind === "symbol" ? "SF Symbol" : "Emoji"}</span>
        <span class="forge-artwork-detail">
          {kind === "symbol" ? (emoji ? "Browse symbols" : symbol) : emoji ? "Change emoji" : "Choose an emoji"}
        </span>
      </span>
      <SymbolIcon name="chevron.right" size={11} strokeWidth={2.5} />
    </button>
  {/if}
  {#each picking?.kind === "emoji" ? [picking] : [] as shown ("emoji")}
    <Popover anchor={shown.anchor} label="Space Icon" onClose={() => (picking = null)}>
      <EmojiPicker title="Space Icon" current={emoji} resetTitle={null}
        onChoose={(chosen) => {
          onWear(`crest.emoji:${chosen}`);
          picking = null;
        }}
        onReset={() => (picking = null)} />
    </Popover>
  {/each}
  {#each picking?.kind === "symbol" ? [picking] : [] as shown ("symbol")}
    <Popover anchor={shown.anchor} label="SF Symbols" onClose={() => (picking = null)}>
      <SymbolPicker current={emoji ? "" : symbol}
        onChoose={(name) => {
          onWear(name);
          picking = null;
        }}
        onDone={() => (picking = null)} />
    </Popover>
  {/each}
</div>
