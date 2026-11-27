import type { ShellTransport } from "@crest/core-client";

/** The longest answer the palette reads, as the Mac's BrowserSearchSuggestionClient takes. */
const maximumResponseBytes = 64 * 1024;
/** How long the palette waits for an answer before it keeps only its own rows. */
const timeout = 5_000;
/** The most suggestions one answer gives. */
const maximumSuggestions = 20;

/**
 * Fetches a search engine's suggestions from the address the core names,
 * as the Mac's BrowserSearchSuggestionClient does: through Crest's Chromium,
 * without cookies or caching, giving up after five seconds or past 64 KB,
 * and reading the OpenSearch answer `[query, [suggestion, …]]`. A failed or
 * unreadable answer gives none, and the palette keeps its own rows.
 */
export async function fetchSuggestions(shell: ShellTransport, address: string): Promise<readonly string[]> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<null>((resolve) => {
    timer = setTimeout(() => resolve(null), timeout);
  });
  try {
    const fetched = await Promise.race([shell.fetchText(address, "searchSuggestions"), late]);
    if (!fetched || fetched.status < 200 || fetched.status > 299 || fetched.text === null) return [];
    if (new TextEncoder().encode(fetched.text).length > maximumResponseBytes) return [];
    return suggestionsIn(fetched.text);
  } catch {
    return [];
  } finally {
    clearTimeout(timer);
  }
}

/** The Mac's BrowserSearchSuggestionResponseParser: the strings of an OpenSearch answer's second entry. */
export function suggestionsIn(text: string): readonly string[] {
  try {
    const payload: unknown = JSON.parse(text);
    if (!Array.isArray(payload) || payload.length < 2 || !Array.isArray(payload[1])) return [];
    return payload[1].filter((value): value is string => typeof value === "string").slice(0, maximumSuggestions);
  } catch {
    return [];
  }
}

/** The palette host's fetcher where Crest's Chromium can fetch, or none in a development window. */
export function suggestionFetcher(shell: ShellTransport | null): ((address: string) => Promise<readonly string[]>) | undefined {
  return shell ? (address) => fetchSuggestions(shell, address) : undefined;
}
