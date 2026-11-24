<script lang="ts" module>
  import type { KeyCombination, ShortcutCommand } from "@crest/contracts";

  /** A question the editor asks before it goes on. */
  type Question =
    | { readonly kind: "conflict"; readonly command: ShortcutCommand; readonly keys: KeyCombination; readonly holders: readonly ShortcutCommand[] }
    | { readonly kind: "resetAll" };

  /** How a `motion.*` without a transition of its own faded: Motion's 0.3 s on its gentler ease. */
  const fade = { duration: 0.3, ease: [0.25, 0.1, 0.35, 1] } as const;
</script>

<script lang="ts">
  import { AssignShortcut, ReassignShortcut, ResetShortcuts, ShortcutSection, UnassignShortcut } from "@crest/contracts";
  import { CoreRejection } from "@crest/core-client";

  import type { Session } from "../boot";
  import { presence } from "../motion";
  import { Sheet } from "../shell/prompts/PromptSheet";
  import { commandTitle, shortcutText } from "../shortcuts";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { useCoreVersion } from "../use-core";
  import ShortcutRow from "./ShortcutRow.svelte";

  /**
   * The Mac's BrowserShortcutSettingsView: a search field and Reset All… over
   * one list of every command by section, each with its keys in a recorder,
   * "Custom" where the person changed them, and a menu that clears them,
   * resets them, and chooses who takes them while a website uses them too.
   * Click a recorder, then press the new keys: Esc cancels, Backspace alone
   * clears. Keys another command holds ask before they move.
   */
  let { session }: { session: Session } = $props();

  const shortcuts = $derived((useCoreVersion(session), session.core.state.shortcuts));
  let search = $state("");
  let recording = $state<string | null>(null);
  let warning = $state<string | null>(null);
  let question = $state.raw<Question | null>(null);
  const send = (intent: Parameters<typeof session.core.send>[0]) => session.core.send(intent);
  const shown = $derived.by(() => {
    const bindings = shortcuts?.bindings ?? [];
    const query = search.trim().toLowerCase();
    return bindings.filter((binding) => !query || commandTitle(binding.command).toLowerCase().includes(query)
      || (binding.command.searchTerms ?? "").toLowerCase().includes(query) || (binding.keys && shortcutText(binding.keys).toLowerCase().includes(query)));
  });

  const assign = (command: ShortcutCommand, keys: KeyCombination) => {
    recording = null;
    send(AssignShortcut({ command, keys })).catch((error: unknown) => {
      if (!(error instanceof CoreRejection)) throw error;
      const rejection = error.rejection;
      if (rejection.$kind === "ShortcutInUse") question = { kind: "conflict", command, keys, holders: rejection.commands };
      else warning = `${shortcutText(keys)} is reserved by Crest.`;
    });
  };
</script>

<div class="shortcuts-editor">
  <div class="shortcuts-controls">
    <span class="settings-search-field">
      <SymbolIcon name="magnifyingglass" size={13} />
      <input bind:value={search} placeholder="Search shortcuts" aria-label="Search shortcuts" />
    </span>
    <button type="button" class="settings-button" disabled={!shortcuts?.isCustomized} onclick={() => (question = { kind: "resetAll" })}>
      Reset All…
    </button>
  </div>
  {#if warning}
    <p class="shortcuts-warning" role="alert" in:presence={{ pose: { opacity: 0 }, timing: fade }} out:presence={{ pose: { opacity: 0 }, timing: fade }}>
      <SymbolIcon name="exclamationmark.triangle.fill" size={12} />{warning}
    </p>
  {/if}
  {#if shown.length === 0}<p class="shortcuts-empty">No Results for “{search}”</p>{/if}
  {#each ShortcutSection.all as section (section.name)}
    {@const rows = shown.filter((binding) => binding.command.section === section)}
    {#if rows.length > 0}
      <section class="settings-group">
        <div class="settings-group-header"><h3>{section.title}</h3></div>
        <div class="settings-card">
          {#each rows as binding (binding.command.name)}
            <ShortcutRow {session} {binding}
              recording={recording === binding.command.name}
              onRecord={(on) => {
                warning = null;
                recording = on ? binding.command.name : null;
              }}
              onKeys={(keys) => assign(binding.command, keys)}
              onClear={() => void send(UnassignShortcut({ command: binding.command })).catch(() => {})}
              onInvalid={() => (warning = "Use a function key, or a key with Ctrl, Alt, or Shift.")} />
          {/each}
        </div>
      </section>
    {/if}
  {/each}
  <p class="settings-footer">Click a shortcut, then press the new keys.</p>
  {#if question}
    {@const asked = question}
    <div class="sheet-backdrop" in:presence={{ pose: { opacity: 0 }, timing: fade }} out:presence={{ pose: { opacity: 0 }, timing: fade }}>
      {#if asked.kind === "conflict"}
        <Sheet title="Shortcut Already in Use" primary="Replace Existing Shortcut" secondary="Cancel" warning
          onPrimary={() => {
            void send(ReassignShortcut({ command: asked.command, keys: asked.keys })).catch(() => {});
            question = null;
          }}
          onEscape={() => (question = null)}>
          <p class="sheet-message">
            {shortcutText(asked.keys)} is assigned to {asked.holders.map(commandTitle).join(", ")}. Replacing it will clear the shortcut from that command.
          </p>
        </Sheet>
      {:else}
        <Sheet title="Reset all Crest shortcuts?" primary="Reset Crest Shortcuts" secondary="Cancel" warning
          onPrimary={() => {
            void send(ResetShortcuts()).catch(() => {});
            question = null;
          }}
          onEscape={() => (question = null)}>
          <p class="sheet-message">Every Crest command will return to its default shortcut.</p>
        </Sheet>
      {/if}
    </div>
  {/if}
</div>
