<script lang="ts">
  import type { ShellTransport } from "@crest/core-client";

  import { DefaultBrowserCheck, useDefaultBrowserCheck } from "../default-browser";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { Button, Group, Row } from "./controls";

  /**
   * BrowserDefaultBrowserSection, as Windows offers it: DefaultBrowserCheck's
   * status, Open Settings… while Crest isn't the default, and Check Again.
   * General settings shows it first, and Setup's last step under its heading.
   */
  let { shell, title }: { shell: ShellTransport | null; title?: string } = $props();

  const check = $derived(new DefaultBrowserCheck(shell));
  const status = $derived(useDefaultBrowserCheck(check).status);
  const isChecking = $derived(useDefaultBrowserCheck(check).isChecking);
</script>

<Group {title} footer={!isChecking && status.message ? status.message : undefined}>
  <Row title="Default browser">
    <span class="settings-buttons default-browser-control">
      {#if isChecking}
        <span class="default-browser-status quiet" data-testid="default-browser-status">
          <span class="settings-progress" aria-hidden="true"></span>
          Checking…
        </span>
      {:else}
        <span class={["default-browser-status", status.tone]} data-testid="default-browser-status">
          <SymbolIcon name={status.symbol} size={14} />
          {status.title}
        </span>
      {/if}
      {#if status.offersSettings}
        <Button onClick={() => check.openSettings()} disabled={!check.canOpenSettings}>Open Settings…</Button>
      {/if}
      <button type="button" class="settings-icon-button" title="Check Again" aria-label="Check Again"
        data-testid="check-default-browser-status" disabled={isChecking} onclick={() => void check.refresh()}>
        <SymbolIcon name="arrow.clockwise" size={13} />
      </button>
    </span>
  </Row>
</Group>
