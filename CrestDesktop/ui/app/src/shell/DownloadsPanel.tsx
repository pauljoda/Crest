import type { DownloadState } from "@crest/contracts";

import { type MouseEvent, useLayoutEffect, useRef, useState } from "react";

import { type Downloads, formatBytes, formatRemaining } from "../downloads";
import { type MenuEntry, showContextMenu } from "../menus";
import { Symbol } from "../symbols";

/**
 * One download as the sidebar's Downloads list shows it, as the Mac's
 * BrowserUtilityDownloadRow: the status icon, the file's name, and beneath
 * it how much has come and how fast, or why it stopped, on one line where
 * the row is wide enough and on two where it isn't; then pause or resume
 * while it transfers, and its one action: allowing it, cancelling it, or
 * once it has finished, the places it can go. A finished file opens with a
 * click, as Windows' browsers open one.
 */
export function DownloadRow({ download, downloads }: { download: DownloadState; downloads: Downloads }) {
  const finished = download.phase.isComplete && download.destination !== null;
  const action = download.phase.primaryAction;
  const row = useRef<HTMLDivElement>(null);
  const [wide, setWide] = useState(false);
  useLayoutEffect(() => {
    const element = row.current;
    if (!element) return;
    const observer = new ResizeObserver(() => setWide(element.clientWidth >= inlineMinimumWidth));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  const presentation = rowPresentation(download);
  const layout = !presentation.hasSecondary ? "single" : wide && !presentation.needsAttention ? "inline" : "stacked";
  return (
    <div ref={row} className={`download-row${download.phase.needsAttention ? " attention" : ""}`}
      onContextMenu={(event) => {
        event.preventDefault();
        void showContextMenu(downloads.shell, event, finishedEntries(download, downloads));
      }}>
      <button className="download-label" disabled={!finished} title={finished ? `Open ${download.filename}` : undefined}
        aria-label={finished ? "Open" : download.filename} aria-description={presentation.spoken}
        onClick={() => downloads.open(download)}>
        <DownloadIcon download={download} />
        <span className="download-text">
          <span className="download-name">{download.filename}</span>
          <span className={`download-details ${layout}`}>
            <span className={presentation.primaryIsStatus && presentation.needsAttention ? "download-danger" : undefined}>
              {presentation.primary}
            </span>
            {layout === "inline" && <span className="download-dot" aria-hidden>·</span>}
            {layout !== "single" && (
              <span className={presentation.secondaryIsStatus && presentation.needsAttention ? "download-danger" : undefined}>
                {presentation.secondary}
              </span>
            )}
          </span>
        </span>
      </button>
      {download.canPause && <RowButton symbol="pause" title="Pause Download" onClick={() => downloads.pause(download)} />}
      {!download.canPause && download.canResume && (
        <RowButton symbol="play" title="Resume Download" onClick={() => downloads.resume(download)} />
      )}
      {action.name === "open" ? (
        finished && (
          <RowButton symbol={action.symbol} title={action.title}
            onClick={(event) => {
              const bounds = event.currentTarget.getBoundingClientRect();
              void showContextMenu(downloads.shell, { clientX: bounds.left, clientY: bounds.bottom }, finishedEntries(download, downloads));
            }} />
        )
      ) : (
        <RowButton symbol={action.symbol} title={action.title} destructive={action.isDestructive}
          onClick={() => perform(downloads, download, action.name)} />
      )}
    </div>
  );
}

/** BrowserDownloadRowPresentation.inlineMinimumWidth. */
const inlineMinimumWidth = 360;

/** Where a finished file can go: opened, shown in its folder, or taken off the list. */
function finishedEntries(download: DownloadState, downloads: Downloads): MenuEntry[] {
  const finished = download.phase.isComplete && download.destination !== null;
  return [
    ...(finished ? [
      { title: "Open", run: () => downloads.open(download) },
      { title: "Show in Folder", run: () => downloads.show(download) },
      "separator" as const,
    ] : []),
    { title: "Remove from List", run: () => downloads.remove(download) },
  ];
}

/**
 * BrowserDownloadRowPresentation: the transfer line, how much has come of
 * how much, or the status while nothing has; and the second line, the rate
 * and time left while it transfers, or else the status.
 */
function rowPresentation(download: DownloadState) {
  const { phase, telemetry } = download;
  const active = phase.isTransferring && !telemetry.isPaused;
  const status = phase.isTransferring && telemetry.isPaused ? "Paused"
    : phase.title ?? download.failure?.message ?? download.message ?? "";
  const showsMetrics = telemetry.bytesReceived > 0n || telemetry.totalBytes !== null || phase.isComplete;
  const rate = active && telemetry.bytesPerSecond ? `${formatBytes(Math.round(Number(telemetry.bytesPerSecond)))}/s` : null;
  const remaining = active && telemetry.estimatedTimeRemaining !== null ? `${formatRemaining(telemetry.estimatedTimeRemaining)} remaining` : null;
  const primary = !showsMetrics ? status
    : telemetry.totalBytes === null ? `${formatBytes(telemetry.bytesReceived)} downloaded`
      : `${formatBytes(telemetry.bytesReceived)} of ${formatBytes(telemetry.totalBytes)} · ${Math.round(download.progress * 100)}%`;
  const secondary = rate && remaining ? `${rate} · ${remaining}` : rate ?? remaining ?? status;
  const showsStatusBeside = showsMetrics && !active;
  return {
    primary,
    secondary,
    primaryIsStatus: !showsMetrics,
    secondaryIsStatus: !rate && !remaining,
    hasSecondary: rate !== null || remaining !== null || showsStatusBeside,
    needsAttention: phase.needsAttention,
    spoken: [status, showsMetrics ? primary : null, rate, remaining].filter(Boolean).join(", "),
  };
}

function perform(downloads: Downloads, download: DownloadState, action: string) {
  if (action === "retry") downloads.retry(download);
  else if (action === "cancel") downloads.cancel(download);
  else if (action === "remove") downloads.remove(download);
  else if (action === "pause") downloads.pause(download);
  else if (action === "resume") downloads.resume(download);
}

function RowButton({ symbol, title, destructive = false, onClick }: {
  symbol: string;
  title: string;
  destructive?: boolean;
  onClick: (event: MouseEvent<HTMLButtonElement>) => void;
}) {
  return (
    <button className={`chrome-button download-action${destructive ? " destructive" : ""}`} aria-label={title}
      title={title} onClick={onClick}>
      <Symbol name={symbol} size={14} />
    </button>
  );
}

/** The phase's symbol, a ring while the file transfers, or else the file's kind. */
function DownloadIcon({ download }: { download: DownloadState }) {
  const { phase } = download;
  if (phase.symbol) {
    return <span className={`download-icon tone-${phase.name}`}><Symbol name={phase.symbol} size={18} /></span>;
  }
  if (phase.isTransferring) {
    return (
      <span className="download-icon">
        <ProgressRing value={download.progress} size={26} />
        <Symbol name={fileKind(download.filename)} size={11} className="download-ring-kind" />
      </span>
    );
  }
  return <span className="download-icon"><Symbol name={fileKind(download.filename)} size={18} /></span>;
}

export function ProgressRing({ value, size }: { value: number; size: number }) {
  const radius = size / 2 - 2;
  const length = 2 * Math.PI * radius;
  const shown = Math.min(Math.max(value, 0.02), 1);
  return (
    <svg className="progress-ring" width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden>
      <circle cx={size / 2} cy={size / 2} r={radius} className="progress-ring-track" />
      <circle cx={size / 2} cy={size / 2} r={radius} className="progress-ring-value"
        strokeDasharray={`${length * shown} ${length}`} transform={`rotate(-90 ${size / 2} ${size / 2})`} />
    </svg>
  );
}

const kinds: readonly (readonly [RegExp, string])[] = [
  [/\.(zip|7z|rar|tar|gz|tgz|bz2|xz|cab)$/i, "doc.zipper"],
  [/\.(png|jpe?g|gif|webp|bmp|svg|heic|avif|ico|tiff?)$/i, "photo"],
  [/\.(mp4|mov|mkv|webm|avi|wmv|m4v)$/i, "film"],
  [/\.(mp3|wav|flac|m4a|aac|ogg|opus|wma)$/i, "music.note"],
  [/\.(pdf|txt|md|rtf|docx?|xlsx?|pptx?|csv|odt|ods)$/i, "doc.text"],
  [/\.(exe|msi|msix|appx|bat|cmd|ps1)$/i, "app"],
];

function fileKind(filename: string): string {
  return kinds.find(([pattern]) => pattern.test(filename))?.[1] ?? "doc";
}
