<script lang="ts">
  import {
    ChooseShortcutPreference,
    type KeyCombination,
    ResetShortcut,
    type ShortcutBinding,
    ShortcutModifiers,
    ShortcutPreference,
  } from "@crest/contracts";
  import { untrack } from "svelte";

  import type { Session } from "../boot";
  import { showContextMenu } from "../menus";
  import { commandTitle, keyCapture, pressedKeys, shortcutText } from "../shortcuts";
  import SymbolIcon from "../SymbolIcon.svelte";

  let { session, binding, recording, onRecord, onKeys, onClear, onInvalid }: {
    session: Session;
    binding: ShortcutBinding;
    recording: boolean;
    onRecord: (on: boolean) => void;
    onKeys: (keys: KeyCombination) => void;
    onClear: () => void;
    onInvalid: () => void;
  } = $props();

  const command = $derived(binding.command);
  let recorder: HTMLButtonElement | undefined;
  // While it records, the window binds no keys, so every key reaches it.
  $effect(() => {
    if (!recording) return;
    return untrack(() => {
      recorder?.focus();
      return keyCapture.begin();
    });
  });
  const menu = (at: { clientX: number; clientY: number }) => void showContextMenu(at, [
    { title: "Clear Shortcut", icon: "delete.left", enabled: binding.keys !== null, run: onClear },
    { title: "Reset to Default", icon: "arrow.counterclockwise", enabled: binding.isCustomized, run: () => void session.core.send(ResetShortcut({ command })).catch(() => {}) },
    ...(binding.choosesPreference ? [
      "separator" as const,
      {
        title: "When a Website Uses These Keys", icon: "keyboard",
        submenu: ShortcutPreference.all.map((preference) => ({
          title: preference.title, icon: preference.symbol,
          checked: binding.preference === preference,
          run: () => void session.core.send(ChooseShortcutPreference({ command, preference })).catch(() => {}),
        })),
      },
    ] : []),
  ]);
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="settings-row shortcut-row" oncontextmenu={(event) => {
  event.preventDefault();
  menu(event);
}}>
  <span class="settings-row-title shortcut-title">{commandTitle(command)}</span>
  {#if binding.isCustomized}<span class="shortcut-custom">Custom</span>{/if}
  <button bind:this={recorder} type="button" class={["shortcut-recorder", recording && "recording"]}
    title="Click, then press the new shortcut" aria-label={`${commandTitle(command)} shortcut`}
    onclick={() => onRecord(!recording)}
    onfocusout={() => recording && onRecord(false)}
    onkeydown={(event) => {
      if (!recording) return;
      event.preventDefault();
      event.stopPropagation();
      const plain = !event.ctrlKey && !event.altKey && !event.shiftKey && !event.metaKey;
      if (plain && event.key === "Escape") return onRecord(false);
      if (plain && (event.key === "Backspace" || event.key === "Delete")) {
        onRecord(false);
        return onClear();
      }
      const keys = pressedKeys(event);
      if (!keys) return;
      // Keys holding the Windows key are the system's, which a window never binds.
      if (keys.modifiers & ShortcutModifiers.Control) return onInvalid();
      const function_ = keys.isSpecialKey && /^f\d+$/.test(keys.key);
      const held = keys.modifiers & (ShortcutModifiers.Command | ShortcutModifiers.Option | ShortcutModifiers.Shift | ShortcutModifiers.Control);
      if (!function_ && !held) return onInvalid();
      onKeys(keys);
    }}>
    {recording ? "Type Shortcut" : binding.keys ? shortcutText(binding.keys) : "—"}
  </button>
  <button type="button" class="shortcut-actions" aria-label="Shortcut Actions" title="Shortcut Actions"
    onclick={(event) => {
      const bounds = event.currentTarget.getBoundingClientRect();
      menu({ clientX: bounds.left, clientY: bounds.bottom });
    }}>
    <SymbolIcon name="ellipsis" size={14} />
  </button>
</div>
