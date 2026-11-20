import {
  AcknowledgeDownloads,
  AnswerDownloadApproval,
  AnswerDownloadDestination,
  CancelDownload,
  type DownloadState,
  PauseDownload,
  RemoveDownload,
  RestartDownload,
  ResumeDownload,
} from "@crest/contracts";
import { useEffect, useRef } from "react";

import type { Session } from "./boot";

/**
 * What a person does with downloads, as the Mac's BrowserDownloadCenter does
 * it: every change to a record is an intent the core hands on to the engine
 * that runs the download, and a finished file opens through the shell.
 */
export class Downloads {
  constructor(private readonly session: Session) {}

  /** The shell that opens and shows finished files, and runs their menus. */
  get shell() {
    return this.session.shell;
  }

  /** A profile's downloads, newest first. */
  of(profileId: string): readonly DownloadState[] {
    return this.session.core.state.downloads.filter((download) => download.profileId === profileId);
  }

  pause(download: DownloadState) {
    if (download.canPause) void this.send(PauseDownload({ downloadId: download.id }));
  }

  resume(download: DownloadState) {
    if (download.canResume) void this.send(ResumeDownload({ downloadId: download.id }));
  }

  cancel(download: DownloadState) {
    if (download.phase.isLive) void this.send(CancelDownload({ downloadId: download.id, message: "Canceled." }));
  }

  retry(download: DownloadState) {
    if (download.phase.canRetry) void this.send(RestartDownload({ downloadId: download.id }));
  }

  /** Clears a record whose download ended; the engine's own list lets it go too. */
  remove(download: DownloadState) {
    if (!download.phase.isLive) void this.send(RemoveDownload({ downloadId: download.id }));
  }

  open(download: DownloadState) {
    if (download.phase.isComplete && download.destination) void this.session.shell?.openDownload(download.destination);
  }

  show(download: DownloadState) {
    if (download.destination) void this.session.shell?.showDownload(download.destination);
  }

  /** The person saw a profile's downloads, so its badge clears. */
  acknowledge(profileId: string) {
    void this.send(AcknowledgeDownloads({ profileId }));
  }

  approve(promptId: string, approved: boolean) {
    void this.send(AnswerDownloadApproval({ promptId, approved }));
  }

  private send(intent: Parameters<Session["core"]["send"]>[0]) {
    // A refused intent changes nothing: the download moved on meanwhile.
    return this.session.core.send(intent).catch(() => undefined);
  }
}

/**
 * Answers where each download's file goes, as the Mac's BrowserDownloadPrompts
 * does: the shell picks the Downloads folder, or the person does in the Save
 * dialog when the engine asks for that, and the first window to ask claims
 * the question.
 */
export function useDownloadDestinations(session: Session) {
  const handled = useRef(new Set<string>());
  const shell = session.shell;
  const version = session.core.state.version;
  useEffect(() => {
    if (!shell) return;
    for (const asked of session.core.state.downloadPrompts.values()) {
      if (asked.$kind !== "DownloadDestinationAsked" || handled.current.has(asked.promptId)) continue;
      handled.current.add(asked.promptId);
      void shell.downloadDestination(asked.promptId, asked.suggestedFilename, asked.forcesPrompt).then((answer) => {
        if ("taken" in answer) return;
        return session.core.send(AnswerDownloadDestination({ promptId: asked.promptId, path: answer.path }));
      }).catch(() => undefined);
    }
  }, [session, shell, version]);
}

const units = ["bytes", "KB", "MB", "GB", "TB"];

/** A size as Windows names one: 1.4 MB. */
export function formatBytes(value: bigint | number): string {
  let size = Number(value);
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  if (unit === 0) return `${size} ${size === 1 ? "byte" : "bytes"}`;
  return `${size >= 100 ? Math.round(size) : size.toFixed(1)} ${units[unit]}`;
}

/** Time left, in the largest units that say it: 2 min, 1 hr 5 min. */
export function formatRemaining(seconds: number): string {
  if (seconds < 60) return `${Math.max(1, Math.round(seconds))} sec`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  return minutes % 60 ? `${hours} hr ${minutes % 60} min` : `${hours} hr`;
}

/** What a download's row says beneath its name. */
export function downloadStatus(download: DownloadState): string {
  const { phase, telemetry } = download;
  if (phase.name === "failed") return download.failure?.message ?? download.message ?? "Failed";
  if (phase.name === "canceled") return download.message ?? "Canceled";
  if (phase.isTransferring) {
    const received = formatBytes(telemetry.bytesReceived);
    const amount = telemetry.totalBytes !== null && telemetry.totalBytes > 0n
      ? `${received} of ${formatBytes(telemetry.totalBytes)}`
      : `${received} downloaded`;
    if (telemetry.isPaused) return `Paused · ${amount}`;
    const rate = telemetry.bytesPerSecond ? ` · ${formatBytes(telemetry.bytesPerSecond)}/s` : "";
    const left = telemetry.estimatedTimeRemaining !== null ? ` · ${formatRemaining(telemetry.estimatedTimeRemaining)} left` : "";
    return `${amount}${rate}${left}`;
  }
  if (phase.isComplete) {
    const size = telemetry.totalBytes ?? telemetry.bytesReceived;
    return size > 0n ? `${phase.title ?? "Completed"} · ${formatBytes(size)}` : (phase.title ?? "Completed");
  }
  return download.message ?? phase.title ?? "";
}

/** The window's downloads, which answer where each file goes while the window is open. */
export function useDownloads(session: Session): Downloads {
  const downloads = useRef<Downloads | null>(null);
  if (!downloads.current) downloads.current = new Downloads(session);
  useDownloadDestinations(session);
  return downloads.current;
}
