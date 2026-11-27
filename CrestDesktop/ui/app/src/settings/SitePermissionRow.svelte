<script lang="ts">
  import { DecideSitePermission, ResetSitePermission, SitePermissionDecision, type SitePermissionRecordState } from "@crest/contracts";

  import type { Session } from "../boot";
  import { showContextMenu } from "../menus";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { send } from "./space-privacy.svelte";

  /** BrowserSitePermissionRecordRow: the site, what it may use, and a menu of the choice. */
  let { session, record }: { session: Session; record: SitePermissionRecordState } = $props();

  const label = $derived(record.detail ? `${record.permission.title} (${record.detail})` : record.permission.title);
  const decide = (decision: SitePermissionDecision) => void send(session, DecideSitePermission({
    spaceId: record.spaceId, origin: record.origin, permission: record.permission, detail: record.detail, decision,
  }));
</script>

<div class="settings-row settings-permission-row">
  <span class="settings-permission-symbol" aria-hidden="true"><SymbolIcon name={record.permission.symbol} size={15} /></span>
  <div class="settings-row-text">
    <span class="settings-row-title settings-truncates">{record.siteName}</span>
    <span class="settings-row-subtitle settings-truncates">{label}</span>
  </div>
  <button type="button" class="settings-menu-button" aria-label={`${label} for ${record.siteName}`}
    onclick={(event) => {
      const bounds = event.currentTarget.getBoundingClientRect();
      void showContextMenu({ clientX: bounds.left, clientY: bounds.bottom }, [
        // The system asks each time for some capabilities, so nothing allows a site ahead of that question.
        ...(record.permission.isAskedBySystem ? [] : [{ title: "Allow", icon: "checkmark.circle", run: () => decide(SitePermissionDecision.grantPersistently) }]),
        { title: "Block", icon: "nosign", run: () => decide(SitePermissionDecision.denyPersistently) },
        "separator",
        { title: "Ask Again", icon: "arrow.counterclockwise", run: () => void send(session, ResetSitePermission({ recordId: record.id })) },
      ]);
    }}>
    {record.decision.title}
    <SymbolIcon name="chevron.up.chevron.down" size={9} />
  </button>
</div>
