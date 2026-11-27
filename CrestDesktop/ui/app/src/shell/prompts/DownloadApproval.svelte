<script lang="ts">
  import type { DownloadApprovalAsked } from "@crest/contracts";
  import type { ShellTransport } from "@crest/core-client";
  import { motion as tokens } from "@crest/design";

  import type { Downloads } from "../../downloads.svelte";
  import { presence } from "../../motion";
  import { useShellFrame } from "../WindowControls.svelte";
  import { Sheet } from "./PromptSheet";

  /**
   * Whether to go on with a download the core judged dangerous before its file
   * has a place, or to keep one its engine warned about while it downloaded,
   * as the Mac asks it: the core's reasons, the engine's warning, where it came
   * from and the Space it belongs to. The window in use asks; keeping a file
   * the engine warned about is never the default, and Escape never downloads.
   */
  let { shell, downloads, asked, spaceName }: {
    shell: ShellTransport;
    downloads: Downloads;
    asked: DownloadApprovalAsked | null;
    spaceName: (spaceId: string | null) => string | null;
  } = $props();

  let answered = $state<string | null>(null);
  const shown = $derived(asked && useShellFrame(shell).active && asked.promptId !== answered ? asked : null);
  const answer = (approved: boolean) => {
    if (!shown) return;
    answered = shown.promptId;
    downloads.approve(shown.promptId, approved);
  };
</script>

<!-- One sheet for both questions, drawn straight in its backdrop so it goes with it. -->
{#snippet question(asked: DownloadApprovalAsked, space: string | null)}
  {@const keeps = asked.warning !== null}
  {@const origin = [asked.sourceHost && `Source: ${asked.sourceHost}`, space && `Space: ${space}`].filter(Boolean).join(" · ")}
  {@const paragraphs = [
    ...asked.reasons.map((reason) => reason.message),
    ...(asked.warning ? [asked.warning.approvalMessage] : []),
    ...(origin ? [origin] : []),
    ...(keeps ? [] : ["Windows marks the finished file as downloaded from the internet. Open it only if you trust its source."]),
  ]}
  <Sheet title={keeps ? `Keep “${asked.filename}”?` : `Download “${asked.filename}”?`} warning
    primary={keeps ? "Cancel" : "Download"} secondary={keeps ? "Keep Download" : "Cancel"}
    onPrimary={() => answer(!keeps)} onSecondary={keeps ? () => answer(true) : undefined} onEscape={() => answer(false)}>
    {#each paragraphs as paragraph, index (index)}
      <p class="sheet-message">{paragraph}</p>
    {/each}
  </Sheet>
{/snippet}

{#each shown ? [shown] : [] as asked (asked.promptId)}
  <div class="sheet-backdrop" in:presence|global={{ pose: { opacity: 0 }, timing: tokens.surface }}
    out:presence={{ pose: { opacity: 0 }, timing: tokens.surface }}>
    {@render question(asked, spaceName(asked.spaceId))}
  </div>
{/each}
