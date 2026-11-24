<script lang="ts" module>
  import { type BrandColor, Tincture } from "@crest/contracts";

  /** The Mac's folderDefault (Slate), the colour a folder or split wears until one is chosen. */
  export const folderDefault: BrandColor = { red: 0.43, green: 0.48, blue: 0.54, alpha: 1 };

  /** BrowserFolderColorPalette: Slate, then the core's tinctures. */
  const colorChoices: readonly { readonly title: string; readonly value: BrandColor }[] = [
    { title: "Slate", value: folderDefault },
    ...["ink", "indigo", "ocean", "sky", "teal", "sage", "gold", "ember", "rose", "sand"].map((name) => {
      const tincture = Tincture.named(name)!;
      return { title: tincture.title, value: tincture.color };
    }),
  ];

  function sameColor(left: BrandColor, right: BrandColor): boolean {
    const near = (a: number, b: number) => Math.abs(a - b) < 0.004;
    return near(left.red, right.red) && near(left.green, right.green) && near(left.blue, right.blue);
  }

  function hexOf(color: BrandColor): string {
    return `#${[color.red, color.green, color.blue].map((part) => Math.round(part * 255).toString(16).padStart(2, "0")).join("")}`;
  }

  function colorOfHex(hex: string): BrandColor {
    const value = Number.parseInt(hex.slice(1), 16);
    return { red: ((value >> 16) & 255) / 255, green: ((value >> 8) & 255) / 255, blue: (value & 255) / 255, alpha: 1 };
  }
</script>

<script lang="ts">
  import { motion as tokens } from "@crest/design";

  import { css } from "../../branding";
  import { presence } from "../../motion";
  import SymbolIcon from "../../SymbolIcon.svelte";

  /**
   * BrowserFolderColorPicker: the title, a reset beside it once a colour was
   * chosen, the house colours as swatches six to a line, and the system's own
   * colour picker for any other.
   */
  let { title, color, resetTitle, onChoose, onReset }: {
    title: string;
    color: BrandColor;
    /** What the reset says, shown while a colour of the person's own is set. */
    resetTitle: string | null;
    onChoose: (color: BrandColor) => void;
    onReset: () => void;
  } = $props();
</script>

<div class="color-picker">
  <div class="picker-header">
    <span class="picker-title">{title}</span>
    {#if resetTitle}
      <button type="button" class="picker-reset" aria-label={resetTitle} title={resetTitle}
        in:presence|global={{ pose: { opacity: 0, scale: 0.72 }, timing: tokens.collection }}
        out:presence={{ pose: { opacity: 0, scale: 0.72 }, timing: tokens.collection }} onclick={onReset}>
        <SymbolIcon name="trash" size={14} />
      </button>
    {/if}
  </div>
  <div class="color-swatches" role="radiogroup" aria-label={title}>
    {#each colorChoices as choice (choice.title)}
      {@const chosen = sameColor(color, choice.value)}
      <button type="button" role="radio" aria-checked={chosen} aria-label={choice.title}
        title={choice.title} class={["color-swatch", chosen && "chosen"]} onclick={() => onChoose(choice.value)}>
        <span style:background={css(choice.value)}></span>
      </button>
    {/each}
  </div>
  <div class="picker-divider"></div>
  <label class="custom-color">
    <span>Custom Color</span>
    <input type="color" value={hexOf(color)} oninput={(event) => onChoose(colorOfHex(event.currentTarget.value))} />
  </label>
</div>
