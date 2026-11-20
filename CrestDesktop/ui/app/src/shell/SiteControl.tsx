import {
  BrowsingDataCategory,
  InspectorPanel,
  OpenInspector,
  type PageState,
  type SiteOrigin,
  SitePermission,
  SitePermissionDecision,
  type SpaceState,
} from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { motion } from "motion/react";
import { type CSSProperties, type MouseEvent, type ReactNode, useEffect, useLayoutEffect, useRef, useState } from "react";

import type { Session } from "../boot";
import type { Browsing } from "../browsing";
import { CopiedLink } from "../copied-link";
import { extensions } from "../extensions";
import { showContextMenu } from "../menus";
import { notices, urlCopiedNotice } from "../notices";
import { Symbol } from "../symbols";
import { type BlockedPopupNotice, noticeTitle } from "./blocked-popups";
import { SiteExtensionsSection } from "./ExtensionActions";
import { originName } from "./prompts/prompt-text";
import {
  clearSiteData, decide, hostOf, permissionTitle, setSiteContentBlocking, siteOriginOf, useSiteContentBlocking, useSiteDecisions,
} from "./site-control";

/**
 * The lock a live site puts in the address field's leading slot, as the
 * Mac's BrowserAddressSecurityButton: it shows whether the connection is
 * secure and, where the page has a certificate, opens it.
 */
export function AddressSecurityButton({ secure, certificate, onReview }: {
  secure: boolean;
  certificate: boolean;
  onReview: () => void;
}) {
  const description = !secure ? "Connection Not Secure" : certificate ? "Review Certificate" : "Connection Secure";
  return (
    <button type="button" className={`address-security${secure ? "" : " insecure"}`} disabled={!certificate}
      aria-label={description} title={description} onClick={onReview}>
      <Symbol name={secure ? "lock.fill" : "lock.open.fill"} size={12} />
    </button>
  );
}

/**
 * The Site Controls trigger at the address field's trailing end, as the
 * Mac's BrowserSiteControlTrigger: in the warning tone, with a dot, while the
 * page has a blocked pop-up to tell of.
 */
export function SiteControlTrigger({ open, notice, onToggle }: {
  open: boolean;
  notice: BlockedPopupNotice | null;
  onToggle: () => void;
}) {
  const label = notice ? `${noticeTitle(notice)}. Site Controls` : "Site Controls";
  return (
    <button type="button" className={`site-control-trigger${open ? " open" : ""}${notice ? " warning" : ""}`}
      aria-label={label} title={label} aria-expanded={open} aria-haspopup="dialog" onClick={onToggle}>
      <Symbol name="slider.horizontal.3" size={12} />
      {notice && <span className="site-control-dot" aria-hidden />}
    </button>
  );
}

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

/**
 * Site Controls, as the Mac's popover lays them out for a page: its title and
 * host, the page's quick actions, how its connection is secured, the
 * permissions its site has in this Space, and clearing what the site keeps.
 * Every choice is the core's; the panel asks it and sends what the person
 * picked. What Windows has no surface for yet, such as region capture, Quick
 * Windows and extensions, waits for it.
 */
export function SiteControlPanel({
  session, browsing, page, space, isPrivate, certificates, notice, onAllowPopups, onClose,
}: SiteControlProps) {
  const panel = useRef<HTMLDivElement>(null);
  // The arrow points at the trigger the panel hangs from, wherever the
  // window's edge leaves the panel.
  const [arrowX, setArrowX] = useState<number | null>(null);
  useLayoutEffect(() => {
    const element = panel.current;
    const area = element?.offsetParent;
    const trigger = area?.querySelector(".site-control-trigger");
    if (!element || !area || !trigger) return;
    const bounds = trigger.getBoundingClientRect();
    setArrowX(bounds.left + bounds.width / 2 - area.getBoundingClientRect().left - element.offsetLeft);
  }, []);
  // The permissions open where the panel first appears, and always for a
  // blocked pop-up, whose permission the notice leads to.
  const [permissionsExpanded, setPermissionsExpanded] = useState(true);
  const address = page.live.url;
  const origin = siteOriginOf(address);
  const host = hostOf(address);
  // The panel goes when the person presses anywhere else or presses Escape.
  useEffect(() => {
    const away = (event: PointerEvent) => {
      const target = event.target as Element | null;
      if (target?.closest(".site-control-panel, .site-control-trigger")) return;
      onClose();
    };
    const escape = (event: KeyboardEvent) => event.key === "Escape" && onClose();
    window.addEventListener("pointerdown", away, true);
    window.addEventListener("keydown", escape);
    panel.current?.focus();
    return () => {
      window.removeEventListener("pointerdown", away, true);
      window.removeEventListener("keydown", escape);
    };
  }, [onClose]);

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

  return (
    <motion.div
      ref={panel}
      className="site-control-panel"
      role="dialog"
      aria-label="Site Controls"
      tabIndex={-1}
      style={arrowX === null ? undefined : { "--arrow-x": `${arrowX}px` } as CSSProperties}
      initial={{ opacity: 0, y: -6, scale: 0.97 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={{ opacity: 0, y: -4, scale: 0.98 }}
      transition={tokens.floatingPane}
    >
      <svg className="site-control-arrow" width="28" height="11" viewBox="0 0 28 11" aria-hidden>
        <path d="M0 11c4 0 6.5-1.6 8.6-3.7l3.6-3.6a2.5 2.5 0 0 1 3.6 0l3.6 3.6C21.5 9.4 24 11 28 11z" fill="currentColor" />
      </svg>
      <div className="site-control-scroll">
        <div className="site-control-content">
          <div className="site-control-header">
            <span className="site-control-title">{page.live.title || "Site Controls"}</span>
            {host && <span className="site-control-host">{host}</span>}
          </div>
          {notice && (
            <div className="site-popup-notice" role="group" aria-label={noticeTitle(notice)}>
              <span className="site-popup-title">
                <Symbol name={notice.status.symbol} size={12} />
                {noticeTitle(notice)}
              </span>
              <span className="site-popup-guidance">{notice.status.guidance}</span>
              {notice.status.offersAllow && (
                <button type="button" className="site-popup-allow"
                  aria-label={`Allow automatic pop-ups for ${notice.origin.host}`}
                  title="Saves this permission in the current Space. Retry the action on the site afterward"
                  onClick={() => {
                    onAllowPopups();
                    setPermissionsExpanded(true);
                  }}>
                  Allow Automatic Pop-ups
                </button>
              )}
            </div>
          )}
          <div className="site-control-actions">
            <QuickAction title="Copy Link" symbol="square.and.arrow.up" onClick={perform(() => void copyLink())} />
            <QuickAction title="Reload" symbol="arrow.clockwise" onClick={perform(() => void browsing.reload(page.id))} />
            <QuickAction title="Inspect" symbol="scope"
              onClick={perform(() => void session.core.request(OpenInspector({ pageId: page.id, panel: InspectorPanel.Elements }))
                .catch(() => undefined))} />
          </div>
          {origin && (
            <>
              <div className="site-control-divider" />
              <SecuritySection page={page} origin={origin} canReview={certificates.length > 0} onReview={reviewCertificate} />
              <SiteBlocking session={session} spaceId={space.id} origin={origin} onChanged={() => void browsing.reload(page.id)} />
              <div className="site-control-divider" />
              <Permissions session={session} spaceId={space.id} origin={origin} expanded={permissionsExpanded}
                onToggle={() => setPermissionsExpanded((expanded) => !expanded)} />
              {session.shell && !isPrivate && (
                <>
                  <div className="site-control-divider" />
                  <SiteExtensionsSection session={session} space={space} pageId={page.id} pageKey={`${page.live.url ?? ""}|${page.live.title}`}
                    onRun={(run) => perform(run)()} onManage={perform(() => extensions.openSettings())} />
                  {webStoreExtensionId(address) && (
                    <button type="button" className="site-control-action labelled"
                      onClick={perform(() => void extensions.install(session, webStoreExtensionId(address)!, space.id, [], page.id))}>
                      <Symbol name="plus" size={12} />
                      <span>Install Extension…</span>
                    </button>
                  )}
                </>
              )}
            </>
          )}
          {host && (
            <>
              <div className="site-control-divider" />
              <div className="site-control-actions">
                {BrowsingDataCategory.all.filter((category) => category.clearsBySite).map((category) => (
                  <button key={category.name} type="button" className="site-control-action labelled"
                    onClick={perform(() => void clearSiteData(session, page, space, category, isPrivate,
                      () => void browsing.reload(page.id, true)))}>
                    <Symbol name={category.symbol ?? "trash"} size={12} />
                    <span>{category.clearSiteTitle ?? category.title}</span>
                  </button>
                ))}
              </div>
            </>
          )}
        </div>
      </div>
    </motion.div>
  );
}

/**
 * Whether the Space blocks ads and trackers on the site, which the Mac offers
 * among a page's actions ("Turn Off Blocking on example.com") and Windows
 * offers where its browsers keep a site's tracking prevention: beside how
 * the connection is secured. Shown only where the Space blocks.
 */
function SiteBlocking({ session, spaceId, origin, onChanged }: {
  session: Session;
  spaceId: string;
  origin: SiteOrigin;
  /** Reloads the page, so the change shows. */
  onChanged: () => void;
}) {
  const blocks = useSiteContentBlocking(session, spaceId, origin);
  if (blocks === null) return null;
  const title = "Block Ads and Trackers";
  return (
    <>
      <div className="site-control-divider" />
      <div className="site-blocking">
        <span className="site-permission-label">
          <Symbol name="shield" size={12} />
          {title}
        </span>
        <button type="button" role="switch" aria-checked={blocks} aria-label={`${title} on ${origin.host}`}
          title={blocks ? `Turn Off Blocking on ${origin.host}` : `Turn On Blocking on ${origin.host}`}
          className={`site-blocking-switch${blocks ? " on" : ""}`}
          onClick={() => void setSiteContentBlocking(session.core, spaceId, origin, !blocks).then((changed) => changed && onChanged())}>
          <span className="site-blocking-knob" />
        </button>
      </div>
    </>
  );
}

/** One of the page's quick actions: a glyph that names itself on hover and to assistive technology. */
function QuickAction({ title, symbol, onClick }: { title: string; symbol: string; onClick: () => void }) {
  return (
    <button type="button" className="site-control-action" aria-label={title} title={title} onClick={onClick}>
      <Symbol name={symbol} size={13} />
    </button>
  );
}

/**
 * How the page's connection is secured, as the Mac's BrowserSiteSecuritySection
 * says it: the origin, the connection's state in its tone, the certificate
 * where there is one, and what the state means. An HTTPS page the engine
 * called secure but gave no certificate for is not called secure.
 */
function SecuritySection({ page, origin, canReview, onReview }: {
  page: PageState; origin: SiteOrigin; canReview: boolean; onReview: () => void;
}) {
  const security = page.live.security;
  const unconfirmed = security.isSecure && origin.scheme === "https" && !canReview;
  const title = unconfirmed ? "Connection Details Unavailable" : security.title;
  const symbol = unconfirmed ? "lock" : security.symbol;
  const tone = unconfirmed ? "quiet" : security.isSecure ? "success" : security.isHazardous ? "danger" : "warning";
  const label: ReactNode = (
    <span className={`site-security-label ${tone}`}>
      <Symbol name={symbol} size={12} />
      {title}
    </span>
  );
  return (
    <div className="site-security">
      <span className="site-security-origin">{originName(origin)}</span>
      {canReview ? (
        <button type="button" className="site-security-review" title="Review Certificate" aria-label="Review Certificate"
          onClick={onReview}>
          {label}
          <span className="site-security-certificate">Certificate</span>
          <Symbol name="chevron.right" size={9} />
        </button>
      ) : label}
      {security.detail && <span className="site-security-detail">{security.detail}</span>}
    </div>
  );
}

/**
 * The site's permissions in this Space, as the Mac's disclosure lists them,
 * open where it first appears: each says the choice that answers it, and
 * opens a menu to ask, allow or block.
 */
function Permissions({ session, spaceId, origin, expanded, onToggle }: {
  session: Session; spaceId: string; origin: SiteOrigin; expanded: boolean; onToggle: () => void;
}) {
  const decisions = useSiteDecisions(session, spaceId, origin);
  const choose = (event: MouseEvent<HTMLButtonElement>, permission: SitePermission, current: SitePermissionDecision) => {
    const bounds = event.currentTarget.getBoundingClientRect();
    const choice = (title: string, decision: SitePermissionDecision) => ({
      title, checked: current === decision, run: () => decide(session.core, spaceId, origin, permission, decision),
    });
    void showContextMenu(session.shell, { clientX: bounds.left, clientY: bounds.bottom }, [
      choice(permission.askChoiceTitle, SitePermissionDecision.ask),
      // The system asks each time for some capabilities, so nothing allows a site ahead of that question.
      ...(permission.isAskedBySystem ? [] : [choice("Allow", SitePermissionDecision.grantPersistently)]),
      choice("Block", SitePermissionDecision.denyPersistently),
    ]);
  };
  return (
    <div className="site-permissions">
      <button type="button" className="site-permissions-toggle" aria-expanded={expanded} onClick={onToggle}>
        <span>Permissions</span>
        <Symbol name={expanded ? "chevron.down" : "chevron.right"} size={9} />
      </button>
      {expanded && SitePermission.all.map((permission) => {
        const decision = decisions?.get(permission.name) ?? SitePermissionDecision.ask;
        return (
          <div key={permission.name} className="site-permission">
            <span className="site-permission-label">
              <Symbol name={permission.symbol} size={12} />
              {permission.title}
            </span>
            <button type="button" className="site-permission-choice" aria-label={`${permission.title}: ${permissionTitle(permission, decision)}`}
              onClick={(event) => choose(event, permission, decision)}>
              {permissionTitle(permission, decision)}
              <Symbol name="chevron.up.chevron.down" size={9} />
            </button>
          </div>
        );
      })}
    </div>
  );
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
