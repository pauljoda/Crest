import type { DownloadState } from "@crest/contracts";
import { animate, motion, useMotionValue, useTransform } from "motion/react";
import { useEffect, useRef, useState } from "react";

import { Symbol } from "../symbols";

/** BrowserDownloadFeedbackEvent.maximumVisible, at most this many at once. */
const maximumVisible = 3;

/** How long before the window opened a download may have been made and still be news, for the core's clock and the window's. */
const startedSlack = 2000;

interface Flight {
  readonly id: string;
  readonly path: { readonly from: Point; readonly to: Point; readonly top: number } | null;
}

interface Point {
  readonly x: number;
  readonly y: number;
}

/**
 * The Mac's download feedback: a download that starts in the window in use
 * flies as a file from the page into the sidebar's lists button, on an arc,
 * shrinking as it goes, and the button takes it in. Where the button isn't on
 * show, or under Reduce Motion, "Download started" says so instead. The
 * engine doesn't say where on the page a download began, so files leave from
 * the middle of the shown card.
 */
export function DownloadFlights({ downloads, profileId, shows }: {
  downloads: readonly DownloadState[];
  /** The profile of the Space the window shows, whose downloads it answers for. */
  profileId: string | null;
  /** Whether the window may show feedback: in use, with no palette over it. */
  shows: boolean;
}) {
  const seen = useRef<Set<string> | null>(null);
  // What the window found as it opened is no news, nor what the core catches
  // it up on after its first frame: only a download made since it opened flies.
  const opened = useRef(Date.now());
  const [flights, setFlights] = useState<readonly Flight[]>([]);
  const ids = downloads.map((download) => download.id).join();
  useEffect(() => {
    const current = new Set(downloads.map((download) => download.id));
    const before = seen.current;
    seen.current = current;
    if (!before) return;
    const arrived = downloads.filter((download) => !before.has(download.id) && download.profileId === profileId
      && download.createdAt.getTime() >= opened.current - startedSlack);
    if (arrived.length === 0 || !shows || !document.hasFocus()) return;
    setFlights((now) => [...now, ...arrived.map((download) => ({ id: download.id, path: pathFor() }))].slice(-maximumVisible));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ids]);
  const land = (id: string) => setFlights((now) => now.filter((flight) => flight.id !== id));
  const announcing = flights.some((flight) => flight.path === null);
  useEffect(() => {
    if (!announcing) return;
    const timer = setTimeout(() => setFlights((now) => now.filter((flight) => flight.path !== null)), 2400);
    return () => clearTimeout(timer);
  }, [announcing]);
  return (
    <div className="download-flights" aria-hidden>
      {flights.map((flight) => flight.path && <FlyingFile key={flight.id} path={flight.path} onLanded={() => land(flight.id)} />)}
      {announcing && (
        <motion.div className="download-started" role="status" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
          style={{ bottom: document.querySelector(".common-lists-button") ? 56 : 16 }}>
          <Symbol name="arrow.down.circle" size={17} />
          Download started
        </motion.div>
      )}
    </div>
  );
}

/** From the middle of the shown card to the lists button, or null where it can't fly. */
function pathFor(): Flight["path"] {
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return null;
  const button = document.querySelector<HTMLElement>(".common-lists-button")?.getBoundingClientRect();
  const card = document.querySelector<HTMLElement>(".space-content-page.live .page-column.focused")?.getBoundingClientRect();
  if (!button || !card || button.width === 0 || button.right < 0) return null;
  return {
    from: { x: card.left + card.width / 2, y: card.top + card.height / 2 },
    to: { x: button.left + button.width / 2, y: button.top + button.height / 2 },
    top: 0,
  };
}

/**
 * BrowserMacDownloadFlightIcon: the file comes up in a beat, then flies along
 * a quadratic arc lifted above both ends by a third of the way, up to 140,
 * shrinking to a third, and fades in the last tenth of the way.
 */
function FlyingFile({ path, onLanded }: { path: NonNullable<Flight["path"]>; onLanded: () => void }) {
  const appearance = useMotionValue(0);
  const progress = useMotionValue(0);
  useEffect(() => {
    let stopped = false;
    const run = async () => {
      await animate(appearance, 1, { duration: 0.14, ease: "easeOut" });
      if (stopped) return;
      await animate(progress, 1, { duration: 0.78, ease: "easeInOut", delay: 0.1 });
      if (!stopped) onLanded();
    };
    void run();
    return () => {
      stopped = true;
    };
    // The flight runs once.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const lift = Math.min(140, Math.hypot(path.to.x - path.from.x, path.to.y - path.from.y) * 0.3);
  const control = { x: (path.from.x + path.to.x) / 2, y: Math.max(path.top + 20, Math.min(path.from.y, path.to.y) - lift) };
  const along = (t: number, a: number, c: number, b: number) => (1 - t) * (1 - t) * a + 2 * (1 - t) * t * c + t * t * b;
  const x = useTransform(progress, (t) => along(t, path.from.x, control.x, path.to.x) - 21);
  const y = useTransform(progress, (t) => along(t, path.from.y, control.y, path.to.y) - 23);
  const scale = useTransform(() => (1 - progress.get() * 0.68) * (0.55 + 0.45 * appearance.get()));
  const opacity = useTransform(() => appearance.get() * (1 - Math.min(Math.max((progress.get() - 0.9) / 0.1, 0), 1)));
  return (
    <motion.div className="flying-file" style={{ x, y, scale, opacity }}>
      <Symbol name="doc.fill" size={28} />
    </motion.div>
  );
}
