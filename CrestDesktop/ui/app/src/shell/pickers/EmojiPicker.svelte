<script lang="ts" module>
  /** Emoji a person often picks for a folder, split or Space, before Windows' own emoji panel. */
  const commonEmoji = [
    "⭐", "❤️", "🔥", "✅", "📌", "📁", "📚", "📝", "💼", "🏠", "🎵", "🎮",
    "🛒", "✈️", "🍔", "☕", "💡", "🧪", "🛠️", "📈", "🎨", "📷", "🌱", "🐶",
  ];

  /** The first emoji in `text`, or null where it holds none. */
  function firstEmoji(text: string): string | null {
    const segments = new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text.trim());
    for (const { segment } of segments) {
      if (/\p{Extended_Pictographic}/u.test(segment)) return segment;
    }
    return null;
  }
</script>

<script lang="ts">
  import { untrack } from "svelte";

  import SymbolIcon from "../../SymbolIcon.svelte";

  /**
   * The Mac's icon customization popover, as Windows offers emoji: the title, a
   * reset to the drawn icon once an emoji was set, a field that takes one emoji
   * (Windows' emoji panel, Win+period, types into it), and the emoji people
   * pick most.
   */
  let { title, current, resetTitle, onChoose, onReset }: {
    title: string;
    current: string | null;
    resetTitle: string | null;
    onChoose: (emoji: string) => void;
    onReset: () => void;
  } = $props();

  let field: HTMLInputElement;
  $effect(() => {
    untrack(() => field.focus());
  });
</script>

<div class="emoji-picker">
  <div class="picker-header">
    <span class="picker-title">{title}</span>
    {#if resetTitle}
      <button type="button" class="picker-reset" aria-label={resetTitle} title={resetTitle} onclick={onReset}>
        <SymbolIcon name="trash" size={14} />
      </button>
    {/if}
  </div>
  <input bind:this={field} class="emoji-field" aria-label="Emoji" placeholder="Type an emoji (Win + .)"
    defaultValue={current ?? ""} oninput={(event) => {
      const emoji = firstEmoji(event.currentTarget.value);
      if (emoji) onChoose(emoji);
    }} />
  <div class="emoji-grid">
    {#each commonEmoji as emoji (emoji)}
      <button type="button" class={["emoji-choice", emoji === current && "chosen"]} aria-label={emoji}
        onclick={() => onChoose(emoji)}>
        {emoji}
      </button>
    {/each}
  </div>
</div>
