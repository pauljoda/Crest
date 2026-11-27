<script lang="ts" module>
  import type { DownloadState } from "@crest/contracts";

  import { type Downloads, formatBytes, formatRemaining } from "../../downloads.svelte";
  import { type MenuEntry, showContextMenu } from "../../menus";

  /** BrowserDownloadRowPresentation.inlineMinimumWidth. */
  const inlineMinimumWidth = 360;

  /** Where a finished file can go: opened, shown in its folder, or taken off the list. */
  function finishedEntries(download: DownloadState, downloads: Downloads): MenuEntry[] {
    const finished = download.phase.isComplete && download.destination !== null;
    return [
      ...(finished ? [
        { title: "Open", icon: "arrow.up.forward.square", run: () => downloads.open(download) },
        { title: "Show in Folder", icon: "magnifyingglass", run: () => downloads.show(download) },
        "separator" as const,
      ] : []),
      { title: "Remove from List", icon: "trash", run: () => downloads.remove(download) },
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
</script>

<script lang="ts">
  import SymbolIcon from "../../SymbolIcon.svelte";
  import ProgressRing from "./ProgressRing.svelte";

  /**
   * One download as the sidebar's Downloads list shows it, as the Mac's
   * BrowserUtilityDownloadRow: the status icon, the file's name, and beneath
   * it how much has come and how fast, or why it stopped, on one line where
   * the row is wide enough and on two where it isn't; then pause or resume
   * while it transfers, and its one action: allowing it, cancelling it, or
   * once it has finished, the places it can go. A finished file opens with a
   * click, as Windows' browsers open one.
   */
  let { download, downloads }: { download: DownloadState; downloads: Downloads } = $props();

  const finished = $derived(download.phase.isComplete && download.destination !== null);
  const action = $derived(download.phase.primaryAction);
  let row: HTMLDivElement;
  let wide = $state(false);
  $effect(() => {
    const element = row;
    const observer = new ResizeObserver(() => {
      wide = element.clientWidth >= inlineMinimumWidth;
    });
    observer.observe(element);
    return () => observer.disconnect();
  });
  const presentation = $derived(rowPresentation(download));
  const layout = $derived(!presentation.hasSecondary ? "single" : wide && !presentation.needsAttention ? "inline" : "stacked");
</script>

{#snippet rowButton(symbol: string, title: string, onClick: (event: MouseEvent & { currentTarget: HTMLButtonElement }) => void,
  destructive = false)}
  <button class={["chrome-button download-action", destructive && "destructive"]} aria-label={title} {title} onclick={onClick}>
    <SymbolIcon name={symbol} size={14} />
  </button>
{/snippet}

<!-- The phase's symbol, a ring while the file transfers, or else the file's kind. -->
{#snippet downloadIcon()}
  {#if download.phase.symbol}
    <span class="download-icon tone-{download.phase.name}"><SymbolIcon name={download.phase.symbol} size={18} /></span>
  {:else if download.phase.isTransferring}
    <span class="download-icon">
      <ProgressRing value={download.progress} size={26} />
      <SymbolIcon name={fileKind(download.filename)} size={11} class="download-ring-kind" />
    </span>
  {:else}
    <span class="download-icon"><SymbolIcon name={fileKind(download.filename)} size={18} /></span>
  {/if}
{/snippet}

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div bind:this={row} class={["download-row", download.phase.needsAttention && "attention"]}
  oncontextmenu={(event) => {
    event.preventDefault();
    void showContextMenu(event, finishedEntries(download, downloads));
  }}>
  <button class="download-label" disabled={!finished} title={finished ? `Open ${download.filename}` : undefined}
    aria-label={finished ? "Open" : download.filename} {...{ "aria-description": presentation.spoken }}
    onclick={() => downloads.open(download)}>
    {@render downloadIcon()}
    <span class="download-text">
      <span class="download-name">{download.filename}</span>
      <span class="download-details {layout}">
        <span class={presentation.primaryIsStatus && presentation.needsAttention ? "download-danger" : undefined}>
          {presentation.primary}
        </span>
        {#if layout === "inline"}<span class="download-dot" aria-hidden="true">·</span>{/if}
        {#if layout !== "single"}
          <span class={presentation.secondaryIsStatus && presentation.needsAttention ? "download-danger" : undefined}>
            {presentation.secondary}
          </span>
        {/if}
      </span>
    </span>
  </button>
  {#if download.canPause}
    {@render rowButton("pause", "Pause Download", () => downloads.pause(download))}
  {/if}
  {#if !download.canPause && download.canResume}
    {@render rowButton("play", "Resume Download", () => downloads.resume(download))}
  {/if}
  {#if action.name === "open"}
    {#if finished}
      {@render rowButton(action.symbol, action.title, (event) => {
        const bounds = event.currentTarget.getBoundingClientRect();
        void showContextMenu({ clientX: bounds.left, clientY: bounds.bottom }, finishedEntries(download, downloads));
      })}
    {/if}
  {:else}
    {@render rowButton(action.symbol, action.title, () => perform(downloads, download, action.name), action.isDestructive)}
  {/if}
</div>
