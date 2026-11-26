<script lang="ts" module>
  import type { PageState, SiteOrigin, SpaceState } from "@crest/contracts";

  import type { Session } from "../../boot";
  import type { Browsing } from "../../browsing";
  import type { BlockedPopupNotice } from "../blocked-popups";

  interface SiteControlProps {
    readonly session: Session;
    readonly browsing: Browsing;
    readonly page: PageState;
    readonly space: SpaceState;
    readonly isPrivate: boolean;
    /** The certificate chain the page's engine verified it with, leaf first, or none. */
    readonly certificates: readonly Uint8Array[];
    /** The page's blocked pop-up, which the panel tells of first. */
    readonly notice: BlockedPopupNotice | null;
    readonly onAllowPopups: () => void;
    readonly onClose: () => void;
  }

  /** The extension a Chrome Web Store listing at `address` is about, as the engine reads it, or null. */
  function webStoreExtensionId(address: string | null): string | null {
    if (!address) return null;
    try {
      const url = new URL(address);
      if (url.protocol !== "https:" || url.hostname !== "chromewebstore.google.com") return null;
      const id = url.pathname.split("/").filter(Boolean).pop() ?? "";
      return /^[a-p]{32}$/.test(id) ? id : null;
    } catch {
      return null;
    }
  }
</script>

<script lang="ts">
  import { BrowsingDataCategory, InspectorPanel, OpenInspector } from "@crest/contracts";
  import { motion as tokens } from "@crest/design";
  import { untrack } from "svelte";

  import { CopiedLink } from "../../copied-link";
  import { extensions } from "../../extensions";
  import { presence } from "../../motion";
  import { notices, urlCopiedNotice } from "../../notices";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { noticeTitle } from "../blocked-popups";
  import { SiteExtensionsSection } from "../ExtensionActions";
  import { originName } from "../prompts/prompt-text";
  import { clearSiteData, hostOf, siteOriginOf } from "../site-control.svelte";
  import Permissions from "./Permissions.svelte";
  import SiteBlocking from "./SiteBlocking.svelte";

  /**
   * Site Controls, as the Mac's popover lays them out for a page: its title and
   * host, the page's quick actions, how its connection is secured, the
   * permissions its site has in this Space, and clearing what the site keeps.
   * Every choice is the core's; the panel asks it and sends what the person
   * picked. What Windows has no surface for yet, such as region capture, Quick
   * Windows and extensions, waits for it.
   */
  let {
    session, browsing, page, space, isPrivate, certificates, notice, onAllowPopups, onClose,
  }: SiteControlProps = $props();

  let panel: HTMLDivElement;
  // The arrow points at the trigger the panel hangs from, wherever the
  // window's edge leaves the panel.
  let arrowX = $state<number | null>(null);
  $effect(() => {
    untrack(() => {
      const element = panel;
      const area = element?.offsetParent;
      const trigger = area?.querySelector(".site-control-trigger");
      if (!element || !area || !trigger) return;
      const bounds = trigger.getBoundingClientRect();
      arrowX = bounds.left + bounds.width / 2 - area.getBoundingClientRect().left - element.offsetLeft;
    });
  });
  // The permissions open where the panel first appears, and always for a
  // blocked pop-up, whose permission the notice leads to.
  let permissionsExpanded = $state(true);
  const address = $derived(page.live.url);
  const origin = $derived(siteOriginOf(address));
  const host = $derived(hostOf(address));
  // The panel goes when the person presses anywhere else or presses Escape.
  $effect(() => {
    const close = onClose;
    untrack(() => {
      const away = (event: PointerEvent) => {
        const target = event.target as Element | null;
        if (target?.closest(".site-control-panel, .site-control-trigger")) return;
        close();
      };
      const escape = (event: KeyboardEvent) => event.key === "Escape" && close();
      window.addEventListener("pointerdown", away, true);
      window.addEventListener("keydown", escape);
      panel?.focus();
      return () => {
        window.removeEventListener("pointerdown", away, true);
        window.removeEventListener("keydown", escape);
      };
    });
  });

  // An action that leaves the panel runs once the panel has gone.
  const perform = (action: () => void) => () => {
    onClose();
    requestAnimationFrame(action);
  };
  const copyLink = async () => {
    if (!session.shell || !address) return;
    await session.shell.copy((await CopiedLink.of(session.core, address)).url);
    notices.post(urlCopiedNotice);
  };
  const reviewCertificate = () => {
    if (certificates.length === 0) return;
    onClose();
    void session.shell?.certificate(certificates);
  };
</script>

<!-- One of the page's quick actions: a glyph that names itself on hover and to assistive technology. -->
{#snippet quickAction(title: string, symbol: string, onClick: () => void)}
  <button type="button" class="site-control-action" aria-label={title} {title} onclick={onClick}>
    <SymbolIcon name={symbol} size={13} />
  </button>
{/snippet}

<!--
  How the page's connection is secured, as the Mac's BrowserSiteSecuritySection
  says it: the origin, the connection's state in its tone, the certificate
  where there is one, and what the state means. An HTTPS page the engine
  called secure but gave no certificate for is not called secure.
-->
{#snippet securitySection(origin: SiteOrigin, canReview: boolean, onReview: () => void)}
  {@const security = page.live.security}
  {@const unconfirmed = security.isSecure && origin.scheme === "https" && !canReview}
  {@const title = unconfirmed ? "Connection Details Unavailable" : security.title}
  {@const symbol = unconfirmed ? "lock" : security.symbol}
  {@const tone = unconfirmed ? "quiet" : security.isSecure ? "success" : security.isHazardous ? "danger" : "warning"}
  {#snippet label()}
    <span class="site-security-label {tone}">
      <SymbolIcon name={symbol} size={12} />
      {title}
    </span>
  {/snippet}
  <div class="site-security">
    <span class="site-security-origin">{originName(origin)}</span>
    {#if canReview}
      <button type="button" class="site-security-review" title="Review Certificate" aria-label="Review Certificate"
        onclick={onReview}>
        {@render label()}
        <span class="site-security-certificate">Certificate</span>
        <SymbolIcon name="chevron.right" size={9} />
      </button>
    {:else}
      {@render label()}
    {/if}
    {#if security.detail}<span class="site-security-detail">{security.detail}</span>{/if}
  </div>
{/snippet}

<!-- It comes in as the Mac's popover does and goes at once, as the system popover crestPopover wraps does (D17). -->
<div
  bind:this={panel}
  class="site-control-panel"
  role="dialog"
  aria-label="Site Controls"
  tabindex="-1"
  style:--arrow-x={arrowX === null ? undefined : `${arrowX}px`}
  in:presence|global={{ pose: { opacity: 0, y: -6, scale: 0.97 }, timing: tokens.floatingPane }}
>
  <svg class="site-control-arrow" width="28" height="11" viewBox="0 0 28 11" aria-hidden="true">
    <path d="M0 11c4 0 6.5-1.6 8.6-3.7l3.6-3.6a2.5 2.5 0 0 1 3.6 0l3.6 3.6C21.5 9.4 24 11 28 11z" fill="currentColor" />
  </svg>
  <div class="site-control-scroll">
    <div class="site-control-content">
      <div class="site-control-header">
        <span class="site-control-title">{page.live.title || "Site Controls"}</span>
        {#if host}<span class="site-control-host">{host}</span>{/if}
      </div>
      {#if notice}
        <div class="site-popup-notice" role="group" aria-label={noticeTitle(notice)}>
          <span class="site-popup-title">
            <SymbolIcon name={notice.status.symbol} size={12} />
            {noticeTitle(notice)}
          </span>
          <span class="site-popup-guidance">{notice.status.guidance}</span>
          {#if notice.status.offersAllow}
            <button type="button" class="setup-button primary site-popup-allow"
              aria-label="Allow automatic pop-ups for {notice.origin.host}"
              title="Saves this permission in the current Space. Retry the action on the site afterward"
              onclick={() => {
                onAllowPopups();
                permissionsExpanded = true;
              }}>
              Allow Automatic Pop-ups
            </button>
          {/if}
        </div>
      {/if}
      <div class="site-control-actions">
        {@render quickAction("Copy Link", "square.and.arrow.up", perform(() => void copyLink()))}
        {@render quickAction("Reload", "arrow.clockwise", perform(() => void browsing.reload(page.id)))}
        {@render quickAction("Inspect", "scope",
          perform(() => void session.core.request(OpenInspector({ pageId: page.id, panel: InspectorPanel.Elements }))
            .catch(() => undefined)))}
      </div>
      <!-- The engine's own section follows the actions, as the Mac's
           BrowserEngineSiteControlsSection does: the page's extensions. -->
      {#if session.shell && !isPrivate}
        <SiteExtensionsSection {session} {space} pageId={page.id} pageKey="{page.live.url ?? ''}|{page.live.title}"
          onRun={(run) => perform(run)()} onManage={perform(() => extensions.openSettings())} />
        {#if webStoreExtensionId(address)}
          <button type="button" class="site-control-action labelled"
            onclick={perform(() => void extensions.install(session, webStoreExtensionId(address)!, space.id, [], page.id))}>
            <SymbolIcon name="plus" size={12} />
            <span>Install Extension…</span>
          </button>
        {/if}
      {/if}
      {#if origin}
        <div class="site-control-divider"></div>
        {@render securitySection(origin, certificates.length > 0, reviewCertificate)}
        <SiteBlocking {session} spaceId={space.id} {origin} onChanged={() => void browsing.reload(page.id)} />
        <div class="site-control-divider"></div>
        <Permissions {session} spaceId={space.id} {origin} expanded={permissionsExpanded}
          onToggle={() => (permissionsExpanded = !permissionsExpanded)} />
      {/if}
      {#if host}
        <div class="site-control-divider"></div>
        <div class="site-control-actions">
          {#each BrowsingDataCategory.all.filter((category) => category.clearsBySite) as category (category.name)}
            <button type="button" class="site-control-action labelled"
              onclick={perform(() => void clearSiteData(session, page, space, category, isPrivate,
                () => void browsing.reload(page.id, true)))}>
              <SymbolIcon name={category.symbol ?? "trash"} size={12} />
              <span>{category.clearSiteTitle ?? category.title}</span>
            </button>
          {/each}
        </div>
      {/if}
    </div>
  </div>
</div>
