<script lang="ts">
  import type { ShortcutBinding, TabState } from "@crest/contracts";
  import { motion as tokens } from "@crest/design";

  import { presence } from "../../motion";
  import { cachedTabIcon } from "../../page-icon.svelte";
  import { shortcutText } from "../../shortcuts";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import type { PaletteItem, PaletteModel } from "../palette-model";
  import { usePaletteVersion } from "./palette-view";
  import ProviderIcon from "./ProviderIcon.svelte";

  let { model, item, section, bindings, tabs, id }: {
    model: PaletteModel; item: PaletteItem; section: string; bindings: readonly ShortcutBinding[]; tabs: readonly TabState[]; id: string;
  } = $props();

  const row = $derived(item.row);
  const selected = $derived.by(() => (usePaletteVersion(model), item.index === model.selectedIndex));
  const intent = $derived(row.kind.isPrimary || section === "topHit");
  const opening = $derived.by(() => (usePaletteVersion(model), selected ? model.openingFor(row) : null));

  /** A tab row wears its tab's icon; a provider row the provider's; any other its symbol. */
  const tab = $derived(row.tabId ? tabs.find((candidate) => candidate.id === row.tabId) : undefined);
  const icon = $derived.by(() => (usePaletteVersion(model), row.tabId ? cachedTabIcon(row.tabId) : null));

  /**
   * What a row says at its end: where it opens while keys are held, else a
   * command's keys, else its kind in the blended list, else what choosing it
   * does.
   */
  const keys = $derived(row.command ? bindings.find((binding) => binding.command.name === row.command!.name)?.keys : null);
  const blurred = { opacity: 0, blur: 4 };
</script>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_interactive_supports_focus -->
<div
  class={["palette-row", selected && "selected"]}
  data-index={item.index}
  {id}
  role="option"
  aria-selected={selected}
  aria-label={row.title}
  onmousemove={() => model.selectResult(item.index)}
  onmousedown={(event) => event.preventDefault()}
  onclick={() => model.activate(row)}
>
  <span class={["palette-row-icon", intent && "intent"]}>
    {#if icon}
      <img src={icon} width={20} height={20} alt="" />
    {:else if row.provider}
      <ProviderIcon provider={row.provider} size={intent ? 18 : 20} />
    {:else}
      <SymbolIcon name={tab?.symbol ?? row.symbol} size={intent ? 18 : 16} />
    {/if}
  </span>
  <div class="palette-row-text">
    <div class="palette-row-title">{row.title}</div>
    {#if row.subtitle}
      <div class="palette-row-detail">{row.subtitle}</div>
    {/if}
  </div>
  <span class="palette-row-spacer"></span>
  <!-- Where it opens keeps a block of its own, ahead of what replaces it, so it lifts out of the row where it stood
       before the replacement comes in, as Motion's popLayout measured it. -->
  {#if opening?.title}
    <span class="palette-row-opening"
      in:presence={{ pose: blurred, timing: tokens.hover, reduced: blurred }}
      out:presence={{ pose: blurred, timing: tokens.hover, reduced: blurred, pop: true }}>
      {opening.title}
    </span>
  {/if}
  {#if !opening?.title}
    {#if keys}
      <span class="palette-shortcut">{shortcutText(keys)}</span>
    {:else if section === "results"}
      <span class="palette-row-kind">{row.kind.label}</span>
    {:else if row.kind.action}
      <span class="palette-row-kind">{row.kind.action}</span>
    {/if}
  {/if}
  <SymbolIcon
    name={selected ? opening!.symbol : intent ? "arrow.turn.down.left" : "arrow.right"}
    size={intent ? 12 : 14}
    class="palette-row-end"
  />
</div>
