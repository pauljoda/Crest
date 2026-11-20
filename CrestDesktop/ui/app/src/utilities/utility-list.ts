import { type ArchivedTabState, ArchiveFilterGroup, type DownloadState, type HistoryEntryState, type SpaceState, TabSurface } from "@crest/contracts";

import { downloadStatus } from "../downloads";

/**
 * The Mac's utility lists (BrowserUtilitySurface and its list model): a
 * Space's archive, its history and its downloads, each searched, filtered
 * and grouped by when, newest first, from the read model alone.
 */

export type UtilitySurfaceName = "archive" | "history" | "downloads";

export interface UtilitySurface {
  readonly name: UtilitySurfaceName;
  readonly title: string;
  readonly symbol: string;
  readonly searchPrompt: string;
  readonly emptyTitle: string;
  readonly emptyDescription: string;
  readonly noResults: (query: string) => string;
  readonly filterLabel: string;
  readonly filters: readonly UtilityFilter[];
  /** Whether the filter menu also offers to clear the Space's history. */
  readonly clearsHistory: boolean;
}

export type UtilityItem =
  | { readonly kind: "archive"; readonly id: string; readonly date: Date; readonly archived: ArchivedTabState }
  | { readonly kind: "history"; readonly id: string; readonly date: Date; readonly entry: HistoryEntryState }
  | { readonly kind: "download"; readonly id: string; readonly date: Date; readonly download: DownloadState };

export interface UtilityFilter {
  readonly name: string;
  readonly title: string;
  readonly symbol: string;
  readonly passes: (item: UtilityItem, now: Date) => boolean;
}

const everything: UtilityFilter = { name: "all", title: "All", symbol: "line.3.horizontal.decrease", passes: () => true };

const archiveFilters: readonly UtilityFilter[] = ArchiveFilterGroup.all.map((group) => ({
  name: `archive.${group.name}`,
  title: group.title,
  symbol: group.symbol,
  passes: (item) => item.kind === "archive" && item.archived.reason.filterGroup.name === group.name,
}));

const sameDay = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();

/** History visited within the last `days` days, or the last month. */
function visitedWithin(name: string, title: string, back: (now: Date) => Date): UtilityFilter {
  return {
    name,
    title,
    symbol: "calendar.badge.clock",
    passes: (item, now) => item.kind === "history" && item.entry.lastVisitedAt >= back(now),
  };
}

const historyFilters: readonly UtilityFilter[] = [
  { name: "history.today", title: "Today", symbol: "calendar", passes: (item, now) => item.kind === "history" && sameDay(item.entry.lastVisitedAt, now) },
  visitedWithin("history.pastWeek", "Past Week", (now) => new Date(now.getFullYear(), now.getMonth(), now.getDate() - 7, now.getHours(), now.getMinutes(), now.getSeconds())),
  visitedWithin("history.pastMonth", "Past Month", (now) => new Date(now.getFullYear(), now.getMonth() - 1, now.getDate(), now.getHours(), now.getMinutes(), now.getSeconds())),
];

const downloadFilters: readonly UtilityFilter[] = [
  { name: "downloads.inProgress", title: "In Progress", symbol: "arrow.down.circle", passes: (item) => item.kind === "download" && item.download.phase.isLive },
  { name: "downloads.finished", title: "Finished", symbol: "checkmark.circle.fill", passes: (item) => item.kind === "download" && item.download.phase.isComplete },
  { name: "downloads.needsAttention", title: "Needs Attention", symbol: "exclamationmark.triangle.fill", passes: (item) => item.kind === "download" && item.download.phase.needsAttention },
];

export const utilitySurfaces: Readonly<Record<UtilitySurfaceName, UtilitySurface>> = {
  archive: {
    name: "archive",
    title: "Archive",
    symbol: "archivebox",
    searchPrompt: "Search Archive…",
    emptyTitle: "No Archived Tabs",
    emptyDescription: "Closed and automatically cleaned tabs from this Space appear here.",
    noResults: (query) => `No archived tabs in this Space match “${query}”.`,
    filterLabel: "Filter Archive",
    filters: [everything, ...archiveFilters],
    clearsHistory: false,
  },
  history: {
    name: "history",
    title: "History",
    symbol: "clock.arrow.circlepath",
    searchPrompt: "Search History…",
    emptyTitle: "No History",
    emptyDescription: "Completed visits from this Space appear here and remain separate from every other Space.",
    noResults: (query) => `No history entries in this Space match “${query}”.`,
    filterLabel: "Filter History",
    filters: [everything, ...historyFilters],
    clearsHistory: true,
  },
  downloads: {
    name: "downloads",
    title: "Downloads",
    symbol: "arrow.down.circle",
    searchPrompt: "Search Downloads…",
    emptyTitle: "No Downloads",
    emptyDescription: "Downloads from this Space appear here.",
    noResults: (query) => `No downloads in this Space match “${query}”.`,
    filterLabel: "Filter Downloads",
    filters: [everything, ...downloadFilters],
    clearsHistory: false,
  },
};

/** The surfaces, in the order the switcher offers them. */
export const utilitySurfaceOrder: readonly UtilitySurfaceName[] = ["archive", "history", "downloads"];

/**
 * A Space's group history, newest visit first: what its primary keeps for
 * the group and what each member kept before it joined (SpaceModel.groupHistory).
 */
export function groupHistory(space: SpaceState, spaces: readonly SpaceState[]): readonly HistoryEntryState[] {
  const primary = space.membership?.primaryId ?? space.id;
  const members = spaces.filter((candidate) => candidate.id === primary || candidate.membership?.primaryId === primary);
  if (members.length <= 1) return space.history;
  return members.flatMap((member) => member.history).sort((a, b) => b.lastVisitedAt.getTime() - a.lastVisitedAt.getTime());
}

/** What `surface` lists for the Space before search and filters. */
export function utilityItems(surface: UtilitySurfaceName, space: SpaceState, spaces: readonly SpaceState[],
  downloads: readonly DownloadState[]): UtilityItem[] {
  switch (surface) {
    case "archive":
      // A Start Page someone closed was never a page to come back to.
      return space.archivedTabs.filter((archived) => archived.tab.surface !== TabSurface.startPage)
        .map((archived) => ({ kind: "archive", id: archived.tab.id, date: archived.archivedAt, archived }));
    case "history":
      return groupHistory(space, spaces).map((entry) => ({ kind: "history", id: entry.id, date: entry.lastVisitedAt, entry }));
    case "downloads": {
      const seen = new Set<string>();
      return downloads.filter((download) => download.profileId === space.profileId && !seen.has(download.id) && !!seen.add(download.id))
        .map((download) => ({ kind: "download", id: download.id, date: download.createdAt, download }));
    }
  }
}

/** Foundation's localizedStandardContains: case and diacritics ignored. */
function contains(text: string | null | undefined, query: string): boolean {
  if (!text) return false;
  const fold = (value: string) => value.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLocaleLowerCase();
  return fold(text).includes(fold(query));
}

function matches(item: UtilityItem, query: string): boolean {
  if (!query) return true;
  switch (item.kind) {
    case "archive": return contains(item.archived.tab.displayTitle, query) || contains(item.archived.tab.url, query);
    case "history": return contains(item.entry.title, query) || contains(item.entry.url, query);
    case "download": return contains(item.download.filename, query) || contains(downloadStatus(item.download), query);
  }
}

export interface UtilitySection {
  readonly id: string;
  readonly title: string;
  readonly items: readonly UtilityItem[];
}

/** BrowserUtilityTimeSection: today, days ago this week, weeks ago up to six, then months. */
function timeSection(date: Date, now: Date): { id: string; title: string } {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const shown = date > now ? now : date;
  const day = new Date(shown.getFullYear(), shown.getMonth(), shown.getDate());
  const daysAgo = Math.max(0, Math.round((today.getTime() - day.getTime()) / 86_400_000));
  if (daysAgo < 7) return { id: `day-${day.getTime()}`, title: daysAgo === 0 ? "Today" : `${daysAgo} days ago` };
  if (daysAgo < 42) {
    const weeks = Math.max(Math.floor(daysAgo / 7), 1);
    return { id: `week-${weeks}`, title: `${weeks} weeks ago` };
  }
  const month = new Date(day.getFullYear(), day.getMonth(), 1);
  return { id: `month-${month.getTime()}`, title: month.toLocaleDateString(undefined, { month: "long", year: "numeric" }) };
}

/** The list's sections: the items that match the search and the filter, newest first, grouped by when. */
export function utilitySections(items: readonly UtilityItem[], query: string, filter: UtilityFilter, now = new Date()): UtilitySection[] {
  const trimmed = query.trim();
  const shown = items.filter((item) => matches(item, trimmed) && filter.passes(item, now))
    .sort((a, b) => b.date.getTime() - a.date.getTime());
  const sections: { id: string; title: string; items: UtilityItem[] }[] = [];
  for (const item of shown) {
    const { id, title } = timeSection(item.date, now);
    const last = sections.at(-1);
    const existing = last?.id === id ? last : sections.find((section) => section.id === id);
    if (existing) existing.items.push(item);
    else sections.push({ id, title, items: [item] });
  }
  return sections;
}

/** A filter of `surface` by name, or everything where it offers none by that name. */
export function filterNamed(surface: UtilitySurface, name: string | null | undefined): UtilityFilter {
  return surface.filters.find((filter) => filter.name === name) ?? everything;
}

// MARK: - The Space's chosen list

const storageKey = "crest.utilities.surface";

/** The list the Common Lists button opens in `spaceId`: the one chosen there, Archive at first. */
export function chosenSurface(spaceId: string): UtilitySurfaceName {
  try {
    const stored = JSON.parse(localStorage.getItem(storageKey) ?? "{}") as Record<string, string>;
    const name = stored[spaceId];
    return name === "history" || name === "downloads" ? name : "archive";
  } catch {
    return "archive";
  }
}

export function chooseSurface(spaceId: string, surface: UtilitySurfaceName) {
  try {
    const stored = JSON.parse(localStorage.getItem(storageKey) ?? "{}") as Record<string, string>;
    stored[spaceId] = surface;
    localStorage.setItem(storageKey, JSON.stringify(stored));
  } catch {
    // The choice lasts this window only.
  }
}
