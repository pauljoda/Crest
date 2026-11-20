import {
  AdoptSitePermissions,
  BrowsingDataCategory,
  BrowsingDataRange,
  ClearHistory,
  type DataRetention,
  DataRetention as Retention,
  type DataRetentionPreferences,
  DeleteBrowsingData,
  DeleteSiteData,
  DecideSitePermission,
  type Intent,
  ReadWebsiteData,
  ResetSitePermission,
  ResetSpacePermissions,
  SetBrowsingPreferences,
  SitePermissionDecision,
  type SitePermissionRecordState,
  type SpaceState,
  type StoredSite,
  SweepExpiredRecords,
} from "@crest/contracts";
import { CoreRejection } from "@crest/core-client";
import { AnimatePresence, motion } from "motion/react";
import { type ReactNode, useCallback, useEffect, useRef, useState } from "react";

import type { Session } from "../boot";
import { showContextMenu } from "../menus";
import { Sheet } from "../shell/prompts/PromptSheet";
import { deletion, websiteData } from "../shell/site-control";
import { Symbol } from "../symbols";
import { useCoreVersion } from "../use-core";
import { Button, Group, Picker, Row, Switch } from "./controls";

/** The group `space` belongs to, as the Mac's BrowserStore finds it: its primary, then every Space that stays in it. */
export function groupOf(space: SpaceState, spaces: readonly SpaceState[]) {
  const primary = spaces.find((candidate) => candidate.id === space.membership?.primaryId) ?? space;
  const members = spaces.filter((candidate) => candidate.id === primary.id || candidate.membership?.primaryId === primary.id);
  return { primary, members };
}

function send(session: Session, intent: Intent) {
  return session.core.send(intent).then(() => true, () => false);
}

/** Words joined as a list in the person's language: "History, Cookies and Site Data, and Cached Images and Files". */
function listed(words: readonly string[]): string {
  return new Intl.ListFormat(navigator.language, { type: "conjunction" }).format(words);
}

/** Whether the window browses privately, so its profiles keep data only in memory. */
function ephemeral(session: Session) {
  return session.core.state.workspaces.get(session.workspaceId)?.kind.isPrivate ?? false;
}

/** The saved choices reach the read model once a window asks the core to publish them. */
let askedForPermissions = false;

/**
 * The Mac's BrowserPrivacySettingsPane for one Space: what it keeps, the
 * choices it saved for sites, the sites that keep data in it, and clearing
 * what it browsed, then a note when its group shares all of that.
 */
export function SpacePrivacySections({ session, space, spaces }: { session: Session; space: SpaceState; spaces: readonly SpaceState[] }) {
  useCoreVersion(session);
  useEffect(() => {
    if (askedForPermissions) return;
    askedForPermissions = true;
    void send(session, AdoptSitePermissions({ records: null }));
  }, [session]);
  const group = groupOf(space, spaces);
  const shared = group.members.length > 1;
  const sites = useWebsiteData(session, space);
  if (sites.locked) {
    return (
      <Group footer="Unlock this Space to see its privacy settings.">
        <Row title={<><Symbol name="lock.fill" size={12} /> {space.settings.name} is locked</>} />
      </Group>
    );
  }
  return (
    <>
      <RetentionSection session={session} space={space} />
      <SitePermissionsSection session={session} space={space} shared={shared} />
      <WebsiteDataSection session={session} space={space} sites={sites} shared={shared} />
      <ClearBrowsingDataSection session={session} space={space} didClear={sites.read} />
      {shared && <p className="settings-footer">Shared by {group.primary.settings.name}’s Sub-Spaces.</p>}
    </>
  );
}

/** A question one of the sections asks before it goes on, as the Mac's confirmation dialogs do. */
function Confirmation({ question }: { question: ReactNode | null }) {
  return (
    <AnimatePresence>
      {question && (
        <motion.div key="question" className="sheet-backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
          {question}
        </motion.div>
      )}
    </AnimatePresence>
  );
}

const retentionChoices = Retention.all.map((value) => ({ value, label: value.title }));

/** BrowserDataRetentionCategory: each record a Space keeps for a while, and what its cleanup deletes. */
const retentionCategories: readonly { readonly field: keyof DataRetentionPreferences; readonly title: string; readonly records: string }[] = [
  { field: "history", title: "History", records: "history entries" },
  { field: "archive", title: "Archived Tabs", records: "archived tabs" },
  { field: "downloads", title: "Download Records", records: "download records" },
];

/** BrowserDataRetentionSettingsSection: how long the Space keeps each record, asking before a shorter time deletes some. */
function RetentionSection({ session, space }: { session: Session; space: SpaceState }) {
  const preferences = space.settings.browsingPreferences;
  const retention = preferences.dataRetention;
  const [pending, setPending] = useState<{ readonly category: (typeof retentionCategories)[number]; readonly proposed: DataRetention } | null>(null);
  const apply = (field: keyof DataRetentionPreferences, proposed: DataRetention) => {
    setPending(null);
    void send(session, SetBrowsingPreferences({
      workspaceId: session.workspaceId, spaceId: space.id, currentTabCleanup: preferences.currentTabCleanup,
      contentBlocking: preferences.contentBlocking, dataRetention: { ...retention, [field]: proposed },
    })).then((kept) => kept && send(session, SweepExpiredRecords({ workspaceId: session.workspaceId })));
  };
  // A shorter time deletes what is older at once, so it asks first.
  const shortens = (previous: DataRetention, proposed: DataRetention) => (proposed.lifetime ?? Infinity) < (previous.lifetime ?? Infinity);
  return (
    <>
      <Group title="Keep" footer="Removing download records doesn’t delete the files.">
        {retentionCategories.map((category) => (
          <Picker key={category.field} title={category.title} value={retention[category.field]} choices={retentionChoices}
            onChange={(proposed) => {
              if (proposed === retention[category.field]) return;
              if (shortens(retention[category.field], proposed)) setPending({ category, proposed });
              else apply(category.field, proposed);
            }} />
        ))}
      </Group>
      <Confirmation question={pending && (
        <Sheet title="Permanently delete older records?" primary={`Use ${pending.proposed.title}`} secondary="Cancel" warning
          onPrimary={() => apply(pending.category.field, pending.proposed)} onEscape={() => setPending(null)}>
          <p className="sheet-message">
            This immediately and permanently deletes {pending.category.records} older than {pending.proposed.title.toLowerCase()} in this Space, including synced copies. Downloaded files stay on disk.
          </p>
        </Sheet>
      )} />
    </>
  );
}

/** BrowserSavedSitePermissionSection: each choice the Space saved for a site, which a menu changes or forgets. */
function SitePermissionsSection({ session, space, shared }: { session: Session; space: SpaceState; shared: boolean }) {
  const records = session.core.state.sitePermissions.get(space.id) ?? [];
  const [resetting, setResetting] = useState(false);
  return (
    <>
      <Group title="Site permissions">
        {records.length === 0 ? (
          <Row title={<span className="settings-secondary-text">No saved permissions</span>} />
        ) : (
          <>
            {records.map((record) => <SitePermissionRow key={record.id} session={session} record={record} />)}
            <div className="settings-row settings-actions-row">
              <span className="settings-actions-status" />
              <Button destructive onClick={() => setResetting(true)}>Reset All…</Button>
            </div>
          </>
        )}
      </Group>
      <Confirmation question={resetting && (
        <Sheet title="Reset All" primary="Reset All" secondary="Cancel" warning
          onPrimary={() => {
            setResetting(false);
            void send(session, ResetSpacePermissions({ spaceId: space.id }));
          }}
          onEscape={() => setResetting(false)}>
          <p className="sheet-message">
            {shared ? "Makes every site ask again in this Space and the others of its group" : "Makes every site ask again in this Space"}
          </p>
        </Sheet>
      )} />
    </>
  );
}

/** BrowserSitePermissionRecordRow: the site, what it may use, and a menu of the choice. */
function SitePermissionRow({ session, record }: { session: Session; record: SitePermissionRecordState }) {
  const label = record.detail ? `${record.permission.title} (${record.detail})` : record.permission.title;
  const decide = (decision: SitePermissionDecision) => void send(session, DecideSitePermission({
    spaceId: record.spaceId, origin: record.origin, permission: record.permission, detail: record.detail, decision,
  }));
  return (
    <div className="settings-row settings-permission-row">
      <span className="settings-permission-symbol" aria-hidden><Symbol name={record.permission.symbol} size={15} /></span>
      <div className="settings-row-text">
        <span className="settings-row-title settings-truncates">{record.siteName}</span>
        <span className="settings-row-subtitle settings-truncates">{label}</span>
      </div>
      <button type="button" className="settings-menu-button" aria-label={`${label} for ${record.siteName}`}
        onClick={(event) => {
          const bounds = event.currentTarget.getBoundingClientRect();
          void showContextMenu(session.shell, { clientX: bounds.left, clientY: bounds.bottom }, [
            // The system asks each time for some capabilities, so nothing allows a site ahead of that question.
            ...(record.permission.isAskedBySystem ? [] : [{ title: "Allow", run: () => decide(SitePermissionDecision.grantPersistently) }]),
            { title: "Block", run: () => decide(SitePermissionDecision.denyPersistently) },
            "separator",
            { title: "Ask Again", run: () => void send(session, ResetSitePermission({ recordId: record.id })) },
          ]);
        }}>
        {record.decision.title}
        <Symbol name="chevron.up.chevron.down" size={9} />
      </button>
    </div>
  );
}

/** BrowserWebsiteDataList: the sites that keep data in the Space's profile, as every engine lists them. */
interface WebsiteData {
  /** The sites, sorted by name, or null until the first listing ends. */
  readonly sites: readonly StoredSite[] | null;
  /** Every engine listed its own sites; one that could not may hide some. */
  readonly complete: boolean;
  /** The Space is locked, so its sites stay hidden. */
  readonly locked: boolean;
  readonly removing: boolean;
  /** The last removal left something an engine could not clear. */
  readonly removalFailed: boolean;
  readonly read: () => void;
  readonly remove: (sites: readonly StoredSite[]) => void;
  readonly removeAll: () => void;
}

function useWebsiteData(session: Session, space: SpaceState): WebsiteData {
  const profileId = space.profileId;
  const [listing, setListing] = useState<{ profileId: string; sites: readonly StoredSite[] | null; complete: boolean; locked: boolean }>(
    { profileId, sites: null, complete: true, locked: false });
  const [removing, setRemoving] = useState(false);
  const [removalFailed, setRemovalFailed] = useState(false);
  const current = useRef(profileId);
  current.current = profileId;
  const read = useCallback(() => {
    const requestId = crypto.randomUUID();
    session.core.send(ReadWebsiteData({ requestId, profileId, ephemeral: ephemeral(session), host: null }))
      .then(() => websiteData(session.core, requestId))
      .then((found) => {
        if (current.current !== profileId) return;
        setListing((previous) => ({
          profileId,
          sites: found ? [...found.sites].sort((left, right) => left.site.localeCompare(right.site)) : (previous.profileId === profileId ? previous.sites : null) ?? [],
          complete: found?.complete ?? false,
          locked: false,
        }));
      }, (error: unknown) => {
        if (current.current !== profileId) return;
        const locked = error instanceof CoreRejection && error.rejection.$kind === "SpaceLocked";
        setListing({ profileId, sites: [], complete: false, locked });
      });
  }, [session, profileId]);
  useEffect(() => {
    setRemovalFailed(false);
    read();
  }, [read]);
  const removingWith = (request: Intent & { requestId: string }) => {
    if (removing) return;
    setRemoving(true);
    void session.core.send(request).then(() => deletion(session.core, request.requestId), () => false).then((deleted) => {
      setRemovalFailed(!deleted);
      setRemoving(false);
      read();
    });
  };
  const bySite = BrowsingDataCategory.all.filter((category) => category.clearsBySite);
  const shown = listing.profileId === profileId ? listing : { sites: null, complete: true, locked: false };
  return {
    sites: shown.sites,
    complete: shown.complete,
    locked: shown.locked,
    removing,
    removalFailed,
    read,
    remove: (sites) => sites.length > 0 && removingWith(DeleteSiteData({
      requestId: crypto.randomUUID(), profileId, ephemeral: ephemeral(session), hosts: sites.map((site) => site.site), categories: bySite,
    })),
    removeAll: () => removingWith(DeleteBrowsingData({
      requestId: crypto.randomUUID(), profileId, ephemeral: ephemeral(session), range: BrowsingDataRange.allTime, categories: bySite,
    })),
  };
}

/** BrowserWebsiteDataSection: the sites that keep data, with Remove for one and Remove All. */
function WebsiteDataSection({ session, space, sites, shared }: { session: Session; space: SpaceState; sites: WebsiteData; shared: boolean }) {
  const [query, setQuery] = useState("");
  const [removingAll, setRemovingAll] = useState(false);
  const wanted = query.trim().toLowerCase();
  const matching = (sites.sites ?? []).filter((site) => !wanted || site.site.toLowerCase().includes(wanted));
  return (
    <>
      <Group title="Website data">
        {sites.sites === null ? (
          <div className="settings-row settings-progress-row"><span className="settings-progress" role="progressbar" aria-label="Loading" /></div>
        ) : sites.sites.length === 0 && sites.complete ? (
          <Row title={<span className="settings-secondary-text">No website data</span>} />
        ) : (
          <>
            {sites.sites.length > 0 && (
              <>
                <div className="settings-row">
                  <span className="settings-search-field settings-row-search">
                    <Symbol name="magnifyingglass" size={13} />
                    <input value={query} placeholder="Search Websites" aria-label="Search Websites" onChange={(event) => setQuery(event.target.value)} />
                  </span>
                </div>
                {matching.map((site) => (
                  <div key={site.site} className="settings-row" onContextMenu={(event) => {
                    event.preventDefault();
                    void showContextMenu(session.shell, event, [{ title: "Remove", run: () => sites.remove([site]) }]);
                  }}>
                    <div className="settings-row-text">
                      <span className="settings-row-title settings-truncates">{site.site}</span>
                      <span className="settings-row-subtitle settings-truncates">{listed(site.kinds.map((kind) => kind.title))}</span>
                    </div>
                    <button type="button" className="settings-button" disabled={sites.removing} aria-label={`Remove data for ${site.site}`}
                      onClick={() => sites.remove([site])}>
                      Remove
                    </button>
                  </div>
                ))}
              </>
            )}
            <div className="settings-row settings-actions-row">
              <span className="settings-actions-status">
                {sites.removalFailed && <><Symbol name="exclamationmark.triangle" size={11} /> Some data couldn’t be removed</>}
              </span>
              <Button destructive disabled={sites.removing} onClick={() => setRemovingAll(true)}>Remove All…</Button>
            </div>
          </>
        )}
        {sites.sites !== null && !sites.complete && (
          <div className="settings-row"><span className="settings-actions-status">Some sites may be missing.</span></div>
        )}
      </Group>
      <Confirmation question={removingAll && (
        <Sheet title={`Remove all website data in “${space.settings.name}”?`} primary="Remove All" secondary="Cancel" warning
          onPrimary={() => {
            setRemovingAll(false);
            sites.removeAll();
          }}
          onEscape={() => setRemovingAll(false)}>
          <p className="sheet-message">
            {shared ? "You’ll be signed out of every site in this Space and the others of its group." : "You’ll be signed out of every site in this Space."}
          </p>
        </Sheet>
      )} />
    </>
  );
}

/**
 * BrowserClearBrowsingDataSection: clearing what the Space browsed within a
 * time range, by category; the core clears its history, and every engine
 * what it keeps for the Space's profile. Other Spaces, passwords,
 * extensions, downloads and permissions stay.
 */
function ClearBrowsingDataSection({ session, space, didClear }: { session: Session; space: SpaceState; didClear: () => void }) {
  const [range, setRange] = useState(BrowsingDataRange.lastHour);
  const [categories, setCategories] = useState<ReadonlySet<BrowsingDataCategory>>(() => new Set(BrowsingDataCategory.all));
  const [confirming, setConfirming] = useState(false);
  const [clearing, setClearing] = useState(false);
  const [outcome, setOutcome] = useState<"cleared" | "failed" | null>(null);
  const chosen = BrowsingDataCategory.all.filter((category) => categories.has(category));
  const clear = async () => {
    setConfirming(false);
    if (chosen.length === 0 || clearing) return;
    setClearing(true);
    let cleared = true;
    if (chosen.some((category) => category.clearsHistory)) {
      cleared = await send(session, ClearHistory({ workspaceId: session.workspaceId, spaceId: space.id, range }));
    }
    const requestId = crypto.randomUUID();
    const erased = await session.core.send(DeleteBrowsingData({ requestId, profileId: space.profileId, ephemeral: ephemeral(session), range, categories: chosen }))
      .then(() => deletion(session.core, requestId), () => false);
    setOutcome(cleared && erased ? "cleared" : "failed");
    setClearing(false);
    didClear();
  };
  return (
    <>
      <Group title="Clear browsing data">
        <Picker title="Time range" value={range} choices={BrowsingDataRange.all.map((value) => ({ value, label: value.title }))}
          onChange={(value) => {
            setRange(value);
            setOutcome(null);
          }} />
        {BrowsingDataCategory.all.map((category) => (
          <Row key={category.name} title={category.title} subtitle={category.detail ?? undefined}>
            <Switch label={category.title} checked={categories.has(category)} onChange={(on) => {
              const next = new Set(categories);
              if (on) next.add(category);
              else next.delete(category);
              setCategories(next);
              setOutcome(null);
            }} />
          </Row>
        ))}
        <div className="settings-row settings-actions-row">
          <span className="settings-actions-status" style={{ opacity: outcome ? 1 : 0 }} aria-hidden={!outcome}>
            <Symbol name={outcome === "failed" ? "exclamationmark.triangle" : "checkmark"} size={11} />
            {outcome === "failed" ? " Couldn’t clear everything" : " Cleared"}
          </span>
          <Button destructive disabled={chosen.length === 0 || clearing} onClick={() => setConfirming(true)}>Clear…</Button>
        </div>
      </Group>
      <Confirmation question={confirming && (
        <Sheet title={`Clear browsing data in “${space.settings.name}”?`} primary="Clear" secondary="Cancel" warning
          onPrimary={() => void clear()} onEscape={() => setConfirming(false)}>
          <p className="sheet-message">{range.title}: {listed(chosen.map((category) => category.title))}. Other Spaces aren’t affected.</p>
        </Sheet>
      )} />
    </>
  );
}
