import type { CrestCore } from "@crest/core-client";
import { type KeyboardEvent, useEffect, useRef } from "react";

import { Symbol } from "../symbols";
import { focusShownPage } from "./PageCard";
import { type FindSession, usePageTools } from "./page-tools";

/**
 * Find in page, as the Mac's BrowserFindBar floats it over the page's top
 * trailing corner: the query, what the search found, the previous and next
 * match, and close. Every ask for find is a request for the field, even
 * while the bar shows; a bar finding again brings back leaves the keys with
 * the page. Return finds the next match and Shift+Return the previous;
 * Escape closes the bar and gives the page the keyboard back.
 */
export function FindBar({ core, pageId }: { core: CrestCore; pageId: string }) {
  const tools = usePageTools();
  const session = tools.find(pageId);
  const field = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (!session.presented || !session.focusesQueryField) return;
    field.current?.focus();
    field.current?.select();
  }, [session.presented, session.focusRequest, session.focusesQueryField]);
  if (!session.presented) return null;

  const close = () => {
    tools.dismiss(core, pageId);
    requestAnimationFrame(focusShownPage);
  };
  const onKeyDown = (event: KeyboardEvent<HTMLElement>) => {
    if (event.key === "Escape") {
      event.preventDefault();
      close();
    } else if (event.key === "Enter" && event.target === field.current && !event.ctrlKey && !event.altKey && !event.metaKey) {
      event.preventDefault();
      tools.search(core, pageId, session.query, event.shiftKey);
    }
  };
  const hasQuery = session.query !== "";
  return (
    <div className="find-bar" role="search" aria-label="Find in Page" data-testid="find-bar" onKeyDown={onKeyDown}>
      <input
        ref={field}
        className="find-field"
        placeholder="Find in Page"
        aria-label="Find in Page"
        spellCheck={false}
        autoComplete="off"
        value={session.query}
        // Typing searches; the same text written back does not.
        onChange={(event) => event.target.value !== session.query && tools.search(core, pageId, event.target.value)}
      />
      <MatchStatus session={session} />
      <button type="button" className="find-control" title="Previous Match" aria-label="Previous Match" disabled={!hasQuery}
        onClick={() => tools.search(core, pageId, session.query, true)}>
        <Symbol name="chevron.up" size={13} />
      </button>
      <button type="button" className="find-control" title="Next Match" aria-label="Next Match" disabled={!hasQuery}
        onClick={() => tools.search(core, pageId, session.query)}>
        <Symbol name="chevron.down" size={13} />
      </button>
      <button type="button" className="find-control" title="Close Find" aria-label="Close Find" onClick={close}>
        <Symbol name="xmark" size={12} />
      </button>
    </div>
  );
}

/**
 * What the page can say about the search, in words, as the Mac's pointer
 * shells spell it: "3 of 12" where the engine counts, else the state, red
 * only where the page has nothing to show; nothing before a search.
 */
function MatchStatus({ session }: { session: FindSession }) {
  const counted = session.matchState === "found" ? session.matches : null;
  if (counted) {
    return (
      <span className="find-status" aria-label={`Match ${counted.active} of ${counted.total}`} data-testid="find-result">
        {counted.active} of {counted.total}
      </span>
    );
  }
  const label = { idle: null, searching: "Searching", found: "Match found", notFound: "No match" }[session.matchState];
  if (!label) return <span className="find-status" />;
  return (
    <span className={`find-status${session.matchState === "notFound" ? " failure" : ""}`} data-testid="find-result">
      {label}
    </span>
  );
}
