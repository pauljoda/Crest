<script lang="ts">
  import {
    phaseDetail, phaseProgress, phaseTitles, softwareUpdates, updateChannels, useSoftwareUpdates,
  } from "../software-update";
  import { Button, Group, Picker, Row, Toggle } from "./controls";

  /**
   * BrowserSoftwareUpdateSettingsSection, as Windows offers it under About:
   * SoftwareUpdates' automatic checks and channel, and Check for Updates…, or
   * where an update stands and what it offers. A copy of Crest that wasn't
   * installed has no updates to follow.
   */
  const phase = $derived(useSoftwareUpdates().phase);
  const isEnabled = $derived(useSoftwareUpdates().isEnabled);
  const channel = $derived(useSoftwareUpdates().channel);
  const checksAutomatically = $derived(useSoftwareUpdates().checksAutomatically);
  const progress = $derived(phaseProgress(phase));
</script>

<Group title="Software updates" footer={isEnabled ? channel.guidance : "Crest updates itself once it is installed."}>
  <Toggle title="Check for updates automatically" checked={checksAutomatically} disabled={!isEnabled}
    onChange={(checks) => softwareUpdates.setChecksAutomatically(checks)} />
  <Picker title="Update channel" value={channel.name} disabled={!isEnabled}
    choices={updateChannels.map((each) => ({ value: each.name, label: each.title }))}
    onChange={(name) => softwareUpdates.setChannel(name)} />
  {#if phase.name === "idle"}
    <div class="settings-row settings-update-actions">
      <Button disabled={!isEnabled} onClick={() => void softwareUpdates.check()}>Check for Updates…</Button>
    </div>
  {:else}
    <Row title={phaseTitles[phase.name]} subtitle={phaseDetail(phase) ?? undefined}>
      {#if phase.name === "checking" || phase.name === "installing"}
        <span class="settings-progress" role="progressbar" aria-label="Software update progress"></span>
      {/if}
      {#if progress !== null}
        <progress class="settings-update-progress" value={progress} max={1} aria-label="Software update progress"></progress>
      {/if}
      {#if phase.name === "available"}
        <Button onClick={() => void softwareUpdates.install()}>Download and Install</Button>
      {/if}
      {#if phase.name === "upToDate" || phase.name === "failed"}
        <Button onClick={() => softwareUpdates.dismiss()}>Dismiss</Button>
      {/if}
    </Row>
  {/if}
</Group>
