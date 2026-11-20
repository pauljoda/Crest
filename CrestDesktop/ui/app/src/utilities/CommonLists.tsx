import type { BrandColor, DownloadState } from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion } from "motion/react";
import { type RefObject, useLayoutEffect, useState } from "react";

import { css, toneOver } from "../branding";
import type { Session } from "../boot";
import { showContextMenu } from "../menus";
import { Symbol } from "../symbols";
import { type UtilitySurfaceName, utilitySurfaceOrder, utilitySurfaces } from "./utility-list";

/**
 * The switcher's page-side accessory, as the Mac's Common Lists button: one
 * control for the archive, history and downloads lists, wearing the symbol of
 * the list it opens, which its menu changes, and badged while downloads have
 * finished unseen, which a press then opens.
 */
export function CommonListsButton({ session, button, expanded, chosen, downloads, newDownloads, badgeColor, onToggle, onChoose }: {
  session: Session;
  button: RefObject<HTMLButtonElement | null>;
  expanded: boolean;
  chosen: UtilitySurfaceName;
  downloads: readonly DownloadState[];
  newDownloads: readonly DownloadState[];
  badgeColor: BrandColor;
  onToggle: () => void;
  onChoose: (surface: UtilitySurfaceName) => void;
}) {
  const opened = newDownloads.length > 0 ? "downloads" : chosen;
  const state = expanded ? "Expanded" : "Collapsed";
  return (
    <motion.button
      ref={button}
      className={`chrome-button common-lists-button${expanded ? " expanded" : ""}`}
      aria-label={utilitySurfaces[opened].title}
      aria-description={newDownloads.length > 0 ? `${state}, ${newDownloads.length} new downloads` : state}
      aria-expanded={expanded}
      title="Archive, History, and Downloads"
      onClick={onToggle}
      onContextMenu={(event) => {
        event.preventDefault();
        void showContextMenu(session.shell, { clientX: event.clientX, clientY: event.clientY }, utilitySurfaceOrder.map((name) => ({
          title: utilitySurfaces[name].title,
          checked: name === chosen,
          run: () => onChoose(name),
        })));
      }}
      whileTap={{ scale: 0.9 }}
      transition={tokens.press}
    >
      <motion.span key={`${opened}-${newDownloads[0]?.id ?? ""}`} className="common-lists-symbol"
        // A download that arrives bounces the symbol, as the Mac's symbol effect does.
        initial={newDownloads.length > 0 ? { scale: 0.7 } : false} animate={{ scale: 1 }}
        transition={{ type: "spring", visualDuration: 0.35, bounce: 0.5 }}>
        <Symbol name={utilitySurfaces[opened].symbol} size={16} strokeWidth={expanded ? 2.25 : 1.75} />
      </motion.span>
      <AnimatePresence>
        {newDownloads.length > 0 && (
          <NotificationBadge key="badge" count={newDownloads.length} tint={badgeTint(downloads, badgeColor)} progress={notificationProgress(downloads)} />
        )}
      </AnimatePresence>
    </motion.button>
  );
}

/** The colour a downloads badge wears: danger while a download needs the person, the Space's colour otherwise. */
function badgeTint(downloads: readonly DownloadState[], accent: BrandColor): BrandColor | "danger" {
  return downloads.some((download) => download.phase.needsAttention) ? "danger" : accent;
}

/** The newest live download's progress, or null when none is live. */
function notificationProgress(downloads: readonly DownloadState[]): number | null {
  const live = downloads.filter((download) => download.phase.isLive);
  if (live.length === 0) return null;
  return live.reduce((newest, download) => (download.createdAt > newest.createdAt ? download : newest)).progress;
}

/**
 * BrowserUtilityNotificationBadge: the count, up to 99, on a capsule of the
 * tint at least 16 points each way, 4 in from its ends, raised 4 points off
 * the button's top trailing corner, and ringed with the newest live
 * download's progress.
 */
function NotificationBadge({ count, tint, progress }: { count: number; tint: BrandColor | "danger"; progress: number | null }) {
  const reads = tint === "danger" ? "light" : toneOver(tint);
  return (
    <motion.span className="utility-badge" aria-hidden
      style={{ background: tint === "danger" ? "var(--danger)" : css(tint), color: reads === "light" ? "white" : "black" }}
      initial={{ scale: 0.4, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} exit={{ scale: 0.4, opacity: 0 }}
      transition={tokens.floatingPane}>
      {Math.min(count, 99)}
      {progress !== null && (
        <svg className="utility-badge-ring" viewBox="0 0 100 100" preserveAspectRatio="none">
          <rect x="0.75" y="0.75" width="98.5" height="98.5" rx="49" ry="49" pathLength={100}
            strokeDasharray={`${Math.max(Math.min(progress, 1), 0.04) * 100} 100`} />
        </svg>
      )}
    </motion.span>
  );
}

/**
 * The Mac's BrowserUtilityFanControl: the archive, history and downloads
 * destinations, fanned out from the lists button onto the page beside the
 * sidebar, a column of glass circles centred on the window, the list shown
 * prominent in the Space's colour. They come out one after another and go
 * back together.
 */
export function UtilityFan({ expanded, trigger, selected, badgeColor, downloads, newDownloadCount, onSelect }: {
  expanded: boolean;
  trigger: RefObject<HTMLButtonElement | null>;
  selected: UtilitySurfaceName | null;
  badgeColor: BrandColor;
  downloads: readonly DownloadState[];
  newDownloadCount: number;
  onSelect: (surface: UtilitySurfaceName) => void;
}) {
  const [geometry, setGeometry] = useState<{ origin: { x: number; y: number }; x: number; y: number } | null>(null);
  useLayoutEffect(() => {
    if (!expanded) return;
    const measure = () => {
      const button = trigger.current?.getBoundingClientRect();
      if (!button) return;
      // Beside the trigger on the page's side: half a button, the gap, and the window's extra offset.
      setGeometry({
        origin: { x: button.left + button.width / 2, y: button.top + button.height / 2 },
        x: button.right + fanButtonSize / 2 + 18 + 12,
        y: window.innerHeight / 2,
      });
    };
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, [expanded, trigger]);
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  return (
    <div className="utility-fan" aria-hidden={!expanded}>
      <AnimatePresence>
        {expanded && geometry && utilitySurfaceOrder.map((name, index) => {
          const surface = utilitySurfaces[name];
          const at = { x: geometry.x, y: geometry.y + (index - 1) * 64 };
          const isSelected = selected === name;
          const symbol = name !== "downloads" ? surface.symbol
            : downloads.some((download) => download.phase.needsAttention) ? "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
              : downloads.some((download) => download.phase.isLive) ? "arrow.down.circle" : "arrow.down.circle.fill";
          return (
            <motion.button
              key={name}
              className={`utility-fan-button${isSelected ? " selected" : ""}`}
              style={{ left: 0, top: 0, ...(isSelected ? { background: css(badgeColor) } : {}) }}
              title={surface.title}
              aria-label={surface.title}
              aria-pressed={isSelected}
              aria-description={isSelected ? "Selected" : name === "downloads" ? `${downloads.length} downloads` : undefined}
              initial={reduce ? false : { x: geometry.origin.x - fanButtonSize / 2, y: geometry.origin.y - fanButtonSize / 2, scale: 0.08, opacity: 0 }}
              animate={{ x: at.x - fanButtonSize / 2, y: at.y - fanButtonSize / 2, scale: 1, opacity: 1 }}
              exit={reduce ? { opacity: 0, transition: { duration: 0 } } : {
                x: geometry.origin.x - fanButtonSize / 2, y: geometry.origin.y - fanButtonSize / 2, scale: 0.08, opacity: 0,
                transition: { duration: 0.18, ease: "easeOut" },
              }}
              transition={reduce ? { duration: 0 } : { ...tokens.utilityFanReveal, delay: index * 0.045 }}
              onClick={() => onSelect(name)}
            >
              <Symbol name={symbol} size={18} strokeWidth={isSelected ? 2.25 : 1.75} />
              {name === "downloads" && newDownloadCount > 0 && (
                <NotificationBadge count={newDownloadCount} tint={badgeTint(downloads, badgeColor)} progress={notificationProgress(downloads)} />
              )}
            </motion.button>
          );
        })}
      </AnimatePresence>
    </div>
  );
}

/** CrestLayout.glassIconButtonDiameter. */
const fanButtonSize = 44;
