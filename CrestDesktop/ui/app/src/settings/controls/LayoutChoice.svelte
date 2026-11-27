<script lang="ts" generics="T extends string">
  import SymbolIcon from "../../SymbolIcon.svelte";

  let { label, choices, value, choose, switcher = false }: {
    label: string; choices: readonly { value: T; label: string }[]; value: T;
    choose: (value: T) => void; switcher?: boolean;
  } = $props();

  const tabs = [
    ["🗂️", "Monday overview"], ["📄", "Launch notes"], ["🧠", "Decision log"], ["✅", "Launch checklist"],
  ];
</script>

<div class="settings-layout-choices" role="radiogroup" aria-label={label}>
  {#each choices as option (option.value)}
    <button type="button" role="radio" aria-checked={option.value === value} onclick={() => choose(option.value)}>
      <span class="settings-preview-face" aria-hidden="true">
        <span class={["settings-preview-window", switcher && "switcher-crop"]}>
          {#if !switcher}
            <span class="preview-caption">● ● ●</span>
            <span class="preview-nav">‹　›　⟳</span>
            <span class={["preview-address", option.value === "top" && "above"]}>⌕　Search or enter website</span>
            <span class="preview-pins">🌐　　 📐　　 📅　　 📁</span>
            <span class="preview-space">♜　Personal</span>
            <span class={["preview-page", option.value === "top" && "below-bar"]}></span>
          {/if}
          <span class="preview-tab-list">
            {#each (switcher ? tabs.slice(1) : tabs) as tab}
              <span class="preview-tab"><span>{tab[0]}</span> {tab[1]}</span>
            {/each}
          </span>
          <span class="preview-switcher">
            {#if option.value === "dots"}<span>●　●　●　●</span>
            {:else}
              <SymbolIcon name="macbook.and.iphone" size={14} /><i></i><i></i><i></i>
            {/if}
          </span>
        </span>
      </span>
      {option.label}
    </button>
  {/each}
</div>
