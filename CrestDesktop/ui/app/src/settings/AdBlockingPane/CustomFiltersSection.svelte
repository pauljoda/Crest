<script lang="ts">
  import { SetCustomFilters } from "@crest/contracts";

  import type { Session } from "../../boot";
  import { Button, Group } from "../controls";

  /**
   * BrowserCustomFiltersSettingsSection: the person's own filters, one rule per
   * line in the lists' syntax. Edits wait for Save, so a half typed rule never
   * applies.
   */
  let { session, saved }: { session: Session; saved: string } = $props();

  // Svelte's element types offer autocorrect on inputs alone, so the editor takes its own as a spread.
  const typing = { autocorrect: "off" };
  let draft = $state<string | null>(null);
  let saveError = $state<string | null>(null);
  const save = () => {
    if (draft === null) return;
    session.core.send(SetCustomFilters({ text: draft })).then(() => {
      draft = null;
      saveError = null;
    }, () => {
      saveError = "These filters are too long to keep.";
    });
  };
</script>

<Group title="My Filters" footer="One rule per line, as filter lists write them.">
  <div class="settings-row settings-editor-row">
    <textarea class="settings-filter-editor" aria-label="My Filters" spellcheck={false} autocapitalize="off" {...typing}
      value={draft ?? saved} placeholder={"example.com##.banner\n||ads.example.com^"}
      oninput={(event) => {
        draft = event.currentTarget.value === saved ? null : event.currentTarget.value;
      }}
      onkeydown={(event) => {
        // Ctrl+S saves, as Windows' editors do; Return stays a new line.
        if (event.key === "s" && event.ctrlKey) {
          event.preventDefault();
          save();
        }
      }}></textarea>
  </div>
  <div class="settings-row settings-actions-row">
    <span class="settings-actions-status">{saveError}</span>
    <span class="settings-buttons">
      <Button disabled={draft === null} onClick={() => {
        draft = null;
        saveError = null;
      }}>Revert</Button>
      <Button disabled={draft === null} onClick={save}>Save</Button>
    </span>
  </div>
</Group>
