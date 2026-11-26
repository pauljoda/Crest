<script lang="ts">
  import type { PageState, PermissionAsked, SpaceState } from "@crest/contracts";
  import { untrack } from "svelte";

  import type { Session } from "../../boot";
  import type { Browsing } from "../../browsing";
  import { isLocked } from "../../spaces/space-access";
  import { coreState, useCoreVersion } from "../../use-core";
  import PermissionPrompt from "../prompts/PermissionPrompt.svelte";
  import { blockedPopups, useBlockedPopups } from "../blocked-popups";
  import { useCertificates } from "../site-control.svelte";
  import { SiteControlPanel } from "../SiteControl";
  import AddressField from "./AddressField.svelte";

  let { session, browsing, space, page, tabUrl, permission, focused = true, activate }: {
    session: Session; browsing: Browsing; space: SpaceState; page: PageState | null; tabUrl: string;
    permission: PermissionAsked | null; focused?: boolean; activate?: () => void;
  } = $props();

  const shownLocked = $derived((useCoreVersion(session), isLocked(session.core, space)));
  // Site Controls act for the shown page while it has an address, and go
  // with the Space or the page they opened for, as the Mac's popover does.
  const siteControlPage = $derived(!shownLocked && page?.live.url ? page : null);
  const certificates = useCertificates(() => ({ session, page: siteControlPage }));
  const popupNotice = $derived.by(() => {
    const popups = useBlockedPopups();
    return siteControlPage ? popups.notice(siteControlPage.id) : null;
  });
  let siteControlsOpen = $state(false);
  const closeSiteControls = () => {
    siteControlsOpen = false;
  };
  $effect(() => {
    void space.id;
    void siteControlPage?.id;
    untrack(closeSiteControls);
  });

  $effect(() => { if (!focused) untrack(closeSiteControls); });
  const live = $derived(shownLocked ? undefined : page?.live);
  // A live site's controls: its lock, which opens its certificate, and Site Controls.
  const addressSite = $derived(siteControlPage ? {
    secure: siteControlPage.live.security.isSecure,
    certificate: certificates.current.length > 0,
    reviewCertificate: () => void session.shell?.certificate(certificates.current),
    open: siteControlsOpen,
    notice: popupNotice,
    toggle: () => {
      siteControlsOpen = !siteControlsOpen;
    },
  } : null);
</script>

<AddressField
  space={space.id} {focused} {activate}
  address={shownLocked ? "" : live?.address ?? live?.url ?? tabUrl}
  site={addressSite}
  secure={live ? live.security.isSecure : !shownLocked && tabUrl.toLowerCase().startsWith("https:")}
  resident={!!page}
  loading={!!live?.isLoading}
  accent="var(--chrome-accent)"
/>
<PermissionPrompt {session} asked={shownLocked ? null : permission} spaceName={space.settings.name} />
{#if siteControlPage && siteControlsOpen && !permission}
  <SiteControlPanel {session} {browsing} page={siteControlPage} {space}
    isPrivate={coreState(session).workspaces.get(session.workspaceId)?.kind.isPrivate ?? false}
    certificates={certificates.current} notice={popupNotice}
    onAllowPopups={() => void blockedPopups.allow(session.core,
      { pageId: siteControlPage.id, spaceId: siteControlPage.spaceId, url: siteControlPage.live.url })}
    onClose={closeSiteControls} />
{/if}
