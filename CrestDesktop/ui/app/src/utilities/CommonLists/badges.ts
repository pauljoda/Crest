import type { BrandColor, DownloadState } from "@crest/contracts";

/** The colour a downloads badge wears: danger while a download needs the person, the Space's colour otherwise. */
export function badgeTint(downloads: readonly DownloadState[], accent: BrandColor): BrandColor | "danger" {
  return downloads.some((download) => download.phase.needsAttention) ? "danger" : accent;
}

/** The newest live download's progress, or null when none is live. */
export function notificationProgress(downloads: readonly DownloadState[]): number | null {
  const live = downloads.filter((download) => download.phase.isLive);
  if (live.length === 0) return null;
  return live.reduce((newest, download) => (download.createdAt > newest.createdAt ? download : newest)).progress;
}
