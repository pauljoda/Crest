import { type ArchivedTabState, type HistoryEntryState, RestoreArchivedTab, type SpaceState, SystemTint } from "@crest/contracts";
import { type MouseEvent, useEffect, useMemo, useState } from "react";

import type { Session } from "../boot";
import type { Downloads } from "../downloads";
import { type MenuEntry, showContextMenu } from "../menus";
import { Symbol } from "../symbols";
import { DownloadRow } from "../shell/DownloadsPanel";
import { TabIcon } from "../shell/Sidebar";
import {
  filterNamed,
  type UtilityItem,
  type UtilitySurfaceName,
  utilityItems,
  utilitySections,
  utilitySurfaces,
} from "./utility-list";

/**
 * A Space's utility list in its sidebar page, in place of its tabs, as the
 * Mac's SpaceSidebarUtilityContent: the search toolbar standing where the
 * address field stood, with its filter menu, and below it the list grouped
 * by when, or what to say when there is nothing to list. A click on the
 * list's blank space puts it away.
 */
export function UtilityList({ session, surface: name, space, spaces, downloads, searchText, onSearchText, filterName, onFilterName,
  onOpenHistory, onRestored, onClearHistory, onDismiss }: {
  session: Session;
  surface: UtilitySurfaceName;
  space: SpaceState;
  spaces: readonly SpaceState[];
  downloads: Downloads | null;
  /** The window's search, which every Space's list shares until the list changes. */
  searchText: string;
  onSearchText: (text: string) => void;
  filterName: string;
  onFilterName: (name: string) => void;
  onOpenHistory: (entry: HistoryEntryState) => void;
  onRestored: (tabId: string) => void;
  onClearHistory: () => void;
  onDismiss: () => void;
}) {
  const surface = utilitySurfaces[name];
  const setSearchText = onSearchText;
  const setFilterName = onFilterName;
  const filter = filterNamed(surface, filterName);

  // The search settles 60 ms after typing stops, as the Mac's list prepares it.
  const [query, setQuery] = useState("");
  useEffect(() => {
    const timer = setTimeout(() => setQuery(searchText), searchText === "" ? 0 : 60);
    return () => clearTimeout(timer);
  }, [searchText]);

  // Downloads seen here are seen.
  const profileDownloads = downloads?.of(space.profileId) ?? [];
  useEffect(() => {
    if (name === "downloads" && downloads && profileDownloads.some((download) => !download.isAcknowledged)) {
      downloads.acknowledge(space.profileId);
    }
  }, [name, downloads, space.profileId, profileDownloads]);

  // Sections refresh at midnight and when a filter's window passes, as the Mac's clock does; a minute is close enough.
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 60_000);
    return () => clearInterval(timer);
  }, []);
  const items = useMemo(() => utilityItems(name, space, spaces, profileDownloads), [name, space, spaces, profileDownloads]);
  const sections = useMemo(() => utilitySections(items, query, filter, now), [items, query, filter, now]);

  const openFilterMenu = (button: HTMLButtonElement) => {
    const bounds = button.getBoundingClientRect();
    const entries: MenuEntry[] = surface.filters.map((option) => ({
      title: option.title,
      checked: option.name === filter.name,
      run: () => setFilterName(option.name),
    }));
    if (surface.clearsHistory) entries.push("separator", { title: "Clear History", run: onClearHistory });
    void showContextMenu(session.shell, { clientX: bounds.left, clientY: bounds.bottom }, entries);
  };

  const restore = async (archived: ArchivedTabState) => {
    const restored = await session.core.send(RestoreArchivedTab({
      workspaceId: session.workspaceId, windowId: session.windowId, spaceId: space.id, tabId: archived.tab.id,
    })).then(() => true, () => false);
    if (restored) onRestored(archived.tab.id);
  };

  const blank = (event: MouseEvent) => {
    if (event.target === event.currentTarget) onDismiss();
  };

  // The list and its toolbar come and go at once, as the Mac's presentation swaps them.
  return (
    <section className="utility-list" aria-label={surface.title}>
      <div className="utility-toolbar">
        <div className="utility-search">
          <Symbol name="magnifyingglass" size={11} strokeWidth={2.25} className="utility-search-glyph" />
          <input
            className="utility-search-input"
            placeholder={surface.searchPrompt}
            aria-label={surface.searchPrompt}
            value={searchText}
            spellCheck={false}
            autoFocus
            onChange={(event) => setSearchText(event.target.value)}
            // Escape clears the search, as a search field's does; it doesn't put the list away.
            onKeyDown={(event) => {
              if (event.key !== "Escape" || !searchText) return;
              event.preventDefault();
              setSearchText("");
            }}
          />
          {searchText && (
            <button className="utility-search-clear" aria-label="Clear" title="Clear" onClick={() => setSearchText("")}>
              <Symbol name="xmark.circle.fill" size={13} />
            </button>
          )}
        </div>
        <button className="utility-filter" aria-label={surface.filterLabel} aria-description={filter.title} title={surface.filterLabel}
          onClick={(event) => openFilterMenu(event.currentTarget)}>
          <Symbol name="line.3.horizontal.decrease" size={15} />
        </button>
      </div>
      {sections.length === 0 ? (
        <div className="utility-empty" onClick={blank}>
          <Symbol name={query.trim() ? "magnifyingglass" : surface.symbol} size={30} />
          <strong>{query.trim() ? "No Results" : surface.emptyTitle}</strong>
          <span>{query.trim() ? surface.noResults(query.trim()) : filter.name !== "all" ? "No items match the selected filter." : surface.emptyDescription}</span>
        </div>
      ) : (
        <div className="utility-sections" onClick={blank}>
          {sections.map((section) => (
            <section key={section.id} className="utility-section" onClick={blank}>
              <h3 className="utility-section-title">{section.title}</h3>
              {section.items.map((item) => (
                <UtilityRow key={item.id} session={session} item={item} space={space} downloads={downloads}
                  onRestore={restore} onOpenHistory={onOpenHistory} />
              ))}
            </section>
          ))}
        </div>
      )}
    </section>
  );
}

function UtilityRow({ session, item, space, downloads, onRestore, onOpenHistory }: {
  session: Session;
  item: UtilityItem;
  space: SpaceState;
  downloads: Downloads | null;
  onRestore: (archived: ArchivedTabState) => void;
  onOpenHistory: (entry: HistoryEntryState) => void;
}) {
  switch (item.kind) {
    case "archive": {
      const { archived } = item;
      const host = hostOf(archived.tab.url);
      return (
        <button className="utility-row" aria-label={`Restore ${archived.tab.displayTitle}`} onClick={() => onRestore(archived)}>
          <span className="utility-row-icon"><TabIcon session={session} tab={archived.tab} pageId={null} /></span>
          <span className="utility-row-text">
            <span className="utility-row-title">{archived.tab.displayTitle}</span>
            <span className="utility-row-subtitle" style={{ color: tintColor(archived.reason.tint) }}>
              <Symbol name={archived.reason.symbol} size={9} strokeWidth={2.5} />
              {` ${archived.reason.title}${host ? ` · ${host}` : ""}`}
            </span>
          </span>
          <span className="utility-row-trailing"><Symbol name="arrow.uturn.backward" size={13} /></span>
        </button>
      );
    }
    case "history": {
      const { entry } = item;
      const host = hostOf(entry.url) ?? entry.url;
      return (
        <button className="utility-row" aria-label={`Open ${entry.title}`} onClick={() => onOpenHistory(entry)}>
          <span className="utility-row-icon"><Symbol name="globe" size={16} /></span>
          <span className="utility-row-text">
            <span className="utility-row-title">{entry.title}</span>
            <span className="utility-row-subtitle">{entry.visitCount > 1 ? `${host} · ${entry.visitCount} visits` : host}</span>
          </span>
          <span className="utility-row-trailing tertiary"><Symbol name="arrow.up.forward" size={13} /></span>
        </button>
      );
    }
    case "download":
      return downloads ? <div className="utility-row-download"><DownloadRow download={item.download} downloads={downloads} /></div> : null;
  }
  void space;
}

function hostOf(url: string | null | undefined): string | null {
  if (!url) return null;
  try {
    return new URL(url).host || null;
  } catch {
    return null;
  }
}

/** The system colour an archive reason wears, in the scheme the sidebar reads in. */
function tintColor(tint: SystemTint): string {
  return `var(--system-${SystemTint[tint].toLowerCase()}, var(--fg-secondary))`;
}
