import {
  AddCustomFilterList,
  ContentBlockingLevel,
  type CustomFilterListState,
  type FilterList,
  FilterListGroup,
  type FilterLists,
  type Intent,
  RefreshFilterLists,
  RemoveCustomFilterList,
  SetContentBlockingLevel,
  SetCustomFilterList,
  SetCustomFilters,
  SetFilterList,
  SetSiteContentBlocking,
  type SiteContentBlocking,
} from "@crest/contracts";
import { CoreRejection } from "@crest/core-client";
import { useEffect, useState } from "react";

import type { Session } from "../boot";
import { filterListUpdater } from "../filter-lists";
import { originName } from "../shell/prompts/prompt-text";
import { Symbol } from "../symbols";
import { useCoreVersion } from "../use-core";
import { Button, Group, Row, Segmented, Toggle } from "./controls";

function send(session: Session, intent: Intent) {
  return session.core.send(intent).then(() => true, () => false);
}

/**
 * The Mac's BrowserAdBlockingSettingsPane: ad blocking holds for every page
 * in every Space, so it has a pane of its own. The level it blocks at, the
 * filter lists that level turns on, the lists the person subscribes to by
 * address, their own rules, and the sites where it blocks nothing.
 * Everything below the level waits while blocking is off.
 */
export function AdBlockingPane({ session }: { session: Session }) {
  useCoreVersion(session);
  const lists = session.core.state.filterLists;
  if (!lists) return null;
  const off = !lists.level.blocksContent;
  return (
    <>
      <LevelSection session={session} lists={lists} />
      <div className={`settings-waits${off ? " off" : ""}`} aria-disabled={off || undefined} inert={off}>
        <FilterListsSection session={session} lists={lists} />
        <CustomListsSection session={session} lists={lists} />
        <CustomFiltersSection session={session} saved={lists.customFilters} />
        <BlockingSitesSection session={session} sites={session.core.state.blockingSites} />
      </div>
    </>
  );
}

/**
 * BrowserAdBlockingLevelSection: Off, Balanced or Strict, each of which sets
 * the lists below to what it turns on. Once the person turns a list against
 * the level, the row says "Customized", and its reset restores the level's
 * lists. That word keeps its place while hidden, so the picker never moves.
 */
export function LevelSection({ session, lists, title }: { session: Session; lists: FilterLists; title?: string }) {
  const choose = (level: ContentBlockingLevel) => void send(session, SetContentBlockingLevel({ level }));
  return (
    <Group title={title} footer={lists.level.summary}>
      <Row title="Blocking" onReset={lists.isCustomized ? () => choose(lists.level) : null}>
        <span className="settings-customized" style={{ opacity: lists.isCustomized ? 1 : 0 }} aria-hidden>Customized</span>
        <Segmented label="Blocking" value={lists.level} onChange={choose}
          choices={ContentBlockingLevel.all.map((level) => ({ value: level, label: level.title }))} />
      </Row>
    </Group>
  );
}

/** When something happened, as the Mac's relative dates name it: "2 hours ago", "yesterday". */
function relative(date: Date): string {
  const seconds = (date.getTime() - Date.now()) / 1000;
  const format = new Intl.RelativeTimeFormat(navigator.language, { numeric: "auto" });
  const units: readonly [Intl.RelativeTimeFormatUnit, number][] = [["year", 31536000], ["month", 2592000], ["week", 604800], ["day", 86400], ["hour", 3600], ["minute", 60]];
  for (const [unit, length] of units) {
    if (Math.abs(seconds) >= length) return format.format(Math.round(seconds / length), unit);
  }
  return format.format(Math.round(seconds), "second");
}

/**
 * BrowserFilterListsSettingsSection: the catalog's lists by group, each on
 * or off as the level set it unless the person turned it themselves, and
 * when they were last updated, with a way to update them now. Lists
 * download and update on their own.
 */
function FilterListsSection({ session, lists }: { session: Session; lists: FilterLists }) {
  const [updating, setUpdating] = useState(false);
  // When the most recently updated list that is on was brought up to date.
  const dates = [
    ...lists.lists.filter((state) => state.isOn).map((state) => state.updatedAt),
    ...lists.customLists.filter((state) => state.list.isOn).map((state) => state.updatedAt),
  ].filter((date): date is Date => date !== null);
  const lastUpdate = dates.length > 0 ? new Date(Math.max(...dates.map((date) => date.getTime()))) : null;
  // A minute's tick keeps "2 minutes ago" true while the pane stays open.
  const [, tick] = useState(0);
  useEffect(() => {
    const timer = setInterval(() => tick((count) => count + 1), 60_000);
    return () => clearInterval(timer);
  }, []);
  const updateNow = async () => {
    if (!(await send(session, RefreshFilterLists()))) return;
    setUpdating(true);
    await filterListUpdater?.check();
    setUpdating(false);
  };
  const turn = (list: FilterList, isOn: boolean) => void send(session, SetFilterList({ list, isOn }));
  return (
    <>
      {FilterListGroup.all.map((group) => {
        const rows = lists.lists.filter((state) => state.list.group === group);
        if (rows.length === 0) return null;
        return (
          <Group key={group.name} title={group.title}>
            {rows.map((state) => (
              <Toggle key={state.list.name} title={state.list.title} checked={state.isOn} onChange={(isOn) => turn(state.list, isOn)}
                subtitle={state.isOn && state.isFailing ? "Couldn’t update" : undefined} />
            ))}
          </Group>
        );
      })}
      <Group>
        <Row title="Updated">
          <span className="settings-secondary-text">{updating ? "Updating…" : lastUpdate ? relative(lastUpdate) : "Not yet"}</span>
          <Button disabled={updating} onClick={() => void updateNow()}>Update Now</Button>
        </Row>
      </Group>
    </>
  );
}

/**
 * BrowserCustomFilterListsSettingsSection: the lists the person subscribes
 * to by address, each with its own switch, which update on their own like
 * the catalog's, and the field that adds another.
 */
function CustomListsSection({ session, lists }: { session: Session; lists: FilterLists }) {
  const [address, setAddress] = useState("");
  const [addError, setAddError] = useState<string | null>(null);
  const add = () => {
    const url = address.trim();
    if (!url) return;
    session.core.send(AddCustomFilterList({ id: crypto.randomUUID(), url })).then(() => {
      setAddress("");
      setAddError(null);
    }, (error: unknown) => {
      const rejection = error instanceof CoreRejection ? error.rejection : null;
      setAddError(rejection?.$kind === "CustomFilterListLimitReached"
        ? `You can add up to ${rejection.limit} lists.` : "Enter an https address.");
    });
  };
  return (
    <Group title="Your Lists" footer="Subscribe to any list by its address. It updates with the built-in lists.">
      {lists.customLists.map((state) => <CustomListRow key={state.list.id} session={session} state={state} />)}
      <div className="settings-row">
        <span className="settings-text-field">
          <input value={address} placeholder="https://example.com/list.txt" aria-label="Filter list address" spellCheck={false}
            autoCapitalize="off" autoCorrect="off" inputMode="url"
            onChange={(event) => setAddress(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") add();
            }} />
        </span>
        <Button disabled={!address.trim()} onClick={add}>Add List</Button>
      </div>
      {addError && <div className="settings-row"><span className="settings-actions-status">{addError}</span></div>}
    </Group>
  );
}

function CustomListRow({ session, state }: { session: Session; state: CustomFilterListState }) {
  const note = state.list.isOn && state.isTooLarge ? "Too large to use" : state.list.isOn && state.isFailing ? "Couldn’t update" : null;
  return (
    <div className="settings-row">
      <div className="settings-row-text">
        <span className="settings-row-title settings-truncates">{state.title}</span>
        <span className="settings-row-subtitle settings-truncates-middle" title={state.list.url}>{state.list.url}</span>
        {note && <span className="settings-row-subtitle">{note}</span>}
      </div>
      <div className="settings-row-control">
        <button type="button" role="switch" aria-checked={state.list.isOn} aria-label={state.title}
          className={`settings-switch${state.list.isOn ? " on" : ""}`}
          onClick={() => void send(session, SetCustomFilterList({ id: state.list.id, isOn: !state.list.isOn }))}>
          <span className="settings-switch-knob" />
        </button>
        <button type="button" className="settings-icon-button" aria-label={`Remove ${state.title}`} title={`Remove ${state.title}`}
          onClick={() => void send(session, RemoveCustomFilterList({ id: state.list.id }))}>
          <Symbol name="minus.circle" size={15} />
        </button>
      </div>
    </div>
  );
}

/**
 * BrowserCustomFiltersSettingsSection: the person's own filters, one rule per
 * line in the lists' syntax. Edits wait for Save, so a half typed rule never
 * applies.
 */
function CustomFiltersSection({ session, saved }: { session: Session; saved: string }) {
  const [draft, setDraft] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const save = () => {
    if (draft === null) return;
    session.core.send(SetCustomFilters({ text: draft })).then(() => {
      setDraft(null);
      setSaveError(null);
    }, () => setSaveError("These filters are too long to keep."));
  };
  return (
    <Group title="My Filters" footer="One rule per line, as filter lists write them.">
      <div className="settings-row settings-editor-row">
        <textarea className="settings-filter-editor" aria-label="My Filters" spellCheck={false} autoCapitalize="off" autoCorrect="off"
          value={draft ?? saved} placeholder={"example.com##.banner\n||ads.example.com^"}
          onChange={(event) => setDraft(event.target.value === saved ? null : event.target.value)}
          onKeyDown={(event) => {
            // Ctrl+S saves, as Windows' editors do; Return stays a new line.
            if (event.key === "s" && event.ctrlKey) {
              event.preventDefault();
              save();
            }
          }} />
      </div>
      <div className="settings-row settings-actions-row">
        <span className="settings-actions-status">{saveError}</span>
        <span className="settings-buttons">
          <Button disabled={draft === null} onClick={() => {
            setDraft(null);
            setSaveError(null);
          }}>Revert</Button>
          <Button disabled={draft === null} onClick={save}>Save</Button>
        </span>
      </div>
    </Group>
  );
}

/** How many sites the section lists before it offers a field that finds one. */
const searchableCount = 10;

/**
 * BrowserBlockingSitesSettingsSection: the sites where Crest blocks nothing,
 * in every Space, each with a way to block on it again. A long list offers a
 * field that finds a site.
 */
function BlockingSitesSection({ session, sites }: { session: Session; sites: readonly SiteContentBlocking[] }) {
  const [query, setQuery] = useState("");
  // One row per site, however many Spaces turned it off.
  const seen = new Set<string>();
  const unique = sites.filter((site) => {
    const key = originName(site.origin);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  const searchable = unique.length > searchableCount;
  const wanted = query.trim().toLowerCase();
  const matches = !searchable || !wanted ? unique : unique.filter((site) => originName(site.origin).toLowerCase().includes(wanted));
  return (
    <Group title="Sites with Blocking Off" footer="Turn blocking off for a site from its Site Controls. Ad blocking settings stay on this device.">
      {searchable && (
        <div className="settings-row">
          <span className="settings-search-field settings-row-search">
            <Symbol name="magnifyingglass" size={13} />
            <input value={query} placeholder="Search Sites" aria-label="Search Sites" onChange={(event) => setQuery(event.target.value)} />
          </span>
        </div>
      )}
      {matches.map((site) => {
        const name = originName(site.origin);
        return (
          <div key={name} className="settings-row">
            <span className="settings-row-title settings-truncates">{name}</span>
            <button type="button" className="settings-icon-button" aria-label={`Turn on blocking for ${name}`} title={`Turn on blocking for ${name}`}
              // Turning it on again from any Space turns it on everywhere.
              onClick={() => void send(session, SetSiteContentBlocking({ spaceId: site.spaceId, origin: site.origin, blocks: true }))}>
              <Symbol name="shield" size={15} />
            </button>
          </div>
        );
      })}
      {unique.length === 0 ? <Row title={<span className="settings-secondary-text">None</span>} />
        : matches.length === 0 ? <Row title={<span className="settings-secondary-text">No Sites Found</span>} /> : null}
    </Group>
  );
}
