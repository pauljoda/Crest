<script lang="ts" module>
  import { reducesMotion } from "../motion";
  import type { FlightPath } from "./FlyingFile.svelte";

  /** BrowserDownloadFeedbackEvent.maximumVisible, at most this many at once. */
  const maximumVisible = 3;

  /** How long before the window opened a download may have been made and still be news, for the core's clock and the window's. */
  const startedSlack = 2000;

  interface Flight {
    readonly id: string;
    readonly path: FlightPath | null;
  }

  /** From the middle of the shown card to the lists button, or null where it can't fly. */
  function pathFor(): Flight["path"] {
    if (reducesMotion()) return null;
    const button = document.querySelector<HTMLElement>(".common-lists-button")?.getBoundingClientRect();
    const card = document.querySelector<HTMLElement>(".space-content-page.live .page-column.focused")?.getBoundingClientRect();
    if (!button || !card || button.width === 0 || button.right < 0) return null;
    return {
      from: { x: card.left + card.width / 2, y: card.top + card.height / 2 },
      to: { x: button.left + button.width / 2, y: button.top + button.height / 2 },
      top: 0,
    };
  }
</script>

<script lang="ts">
  import type { DownloadState } from "@crest/contracts";
  import { untrack } from "svelte";

  import SymbolIcon from "../SymbolIcon.svelte";
  import FlyingFile from "./FlyingFile.svelte";
  import { motionDefaults } from "./motion-defaults";

  /**
   * The Mac's download feedback: a download that starts in the window in use
   * flies as a file from the page into the sidebar's lists button, on an arc,
   * shrinking as it goes, and the button takes it in. Where the button isn't on
   * show, or under Reduce Motion, "Download started" says so instead. The
   * engine doesn't say where on the page a download began, so files leave from
   * the middle of the shown card.
   */
  let { downloads, profileId, shows }: {
    downloads: readonly DownloadState[];
    /** The profile of the Space the window shows, whose downloads it answers for. */
    profileId: string | null;
    /** Whether the window may show feedback: in use, with no palette over it. */
    shows: boolean;
  } = $props();

  let seen: Set<string> | null = null;
  // What the window found as it opened is no news, nor what the core catches
  // it up on after its first frame: only a download made since it opened flies.
  const opened = Date.now();
  let flights = $state.raw<readonly Flight[]>([]);
  const ids = $derived(downloads.map((download) => download.id).join());
  $effect(() => {
    void ids;
    untrack(() => {
      const current = new Set(downloads.map((download) => download.id));
      const before = seen;
      seen = current;
      if (!before) return;
      const arrived = downloads.filter((download) => !before.has(download.id) && download.profileId === profileId
        && download.createdAt.getTime() >= opened - startedSlack);
      if (arrived.length === 0 || !shows || !document.hasFocus()) return;
      flights = [...flights, ...arrived.map((download) => ({ id: download.id, path: pathFor() }))].slice(-maximumVisible);
    });
  });
  const land = (id: string) => {
    flights = flights.filter((flight) => flight.id !== id);
  };
  const announcing = $derived(flights.some((flight) => flight.path === null));
  $effect(() => {
    if (!announcing) return;
    const timer = setTimeout(() => {
      flights = flights.filter((flight) => flight.path !== null);
    }, 2400);
    return () => clearTimeout(timer);
  });
  // The notice sits above the lists button where there is one, as the window draws it now.
  const bottom = $derived.by(() => {
    void downloads;
    void flights;
    return document.querySelector(".common-lists-button") ? 56 : 16;
  });
</script>

<!-- The flights are only drawn; "Download started" is told. -->
<div class="download-flights">
  {#each flights as flight (flight.id)}
    {#if flight.path}
      <FlyingFile path={flight.path} onLanded={() => land(flight.id)} />
    {/if}
  {/each}
  {#if announcing}
    <div class="download-started" role="status" style:bottom="{bottom}px" in:motionDefaults={{ pose: { opacity: 0, y: 8 } }}>
      <SymbolIcon name="arrow.down.circle" size={17} />
      Download started
    </div>
  {/if}
</div>
