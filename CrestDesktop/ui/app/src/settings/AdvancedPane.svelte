<script lang="ts">
  import { SetupEntry } from "@crest/contracts";

  import { setupLauncher } from "../commands";
  import { Group } from "./controls";

  /**
   * BrowserAdvancedSettingsPane's Setup section: Crest Setup again from the
   * welcome, or its Spaces to review and change, over this window. The Mac's
   * Import from Another Browser waits for Windows to read other browsers.
   */
</script>

<Group title="Setup">
  <button type="button" class="settings-row settings-link-row settings-action-row" title="Restart setup from the welcome screen"
    data-testid="settings-rerun-onboarding" onclick={() => setupLauncher.open(SetupEntry.rerun)}>
    <span class="settings-row-title">Rerun onboarding</span>
  </button>
  <button type="button" class="settings-row settings-link-row settings-action-row" title="Customize current Spaces or add new Spaces"
    data-testid="settings-manual-setup" onclick={() => setupLauncher.open(SetupEntry.manualSetup)}>
    <span class="settings-row-title">Review &amp; Customize Setup…</span>
  </button>
</Group>
