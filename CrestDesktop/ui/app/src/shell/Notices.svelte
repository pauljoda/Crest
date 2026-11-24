<script lang="ts" module>
  import type { WindowNotice } from "../notices";

  interface ShownNotice extends WindowNotice {
    readonly id: number;
  }

  /**
   * What the shell reports in Chromium's name: what a feature Crest does not
   * offer here would have shown (UnavailableFeature in crest_desktop_host.h, in
   * its order), with the Mac's own words for each.
   */
  const unavailable: readonly (readonly [message: string, symbol: string])[] = [
    ["Autofill is not connected in Crest yet.", "person"],
    ["Payment autofill is not available in Crest yet.", "creditcard"],
    ["Address autofill is not available in Crest yet.", "person.text.rectangle"],
    ["Autofill with AI is not available in Crest yet.", "sparkles"],
    ["Profiles are not available in Crest yet.", "person.crop.circle"],
    ["The eye dropper is not available in Crest yet.", "eyedropper"],
    ["Caret browsing is not available in Crest yet.", "text.cursor"],
    ["This private browsing option is not available in Crest yet.", "eye.slash"],
    ["Chrome Labs is not available in Crest.", "flask"],
    ["Translating a selection is not available in Crest yet.", "translate"],
  ];
  const fallback = ["This is not available in Crest yet.", "info.circle"] as const;
</script>

<script lang="ts">
  import type { ShellTransport } from "@crest/core-client";
  import { motion as tokens } from "@crest/design";

  import { presence } from "../motion";
  import { noticeDuration, notices } from "../notices";
  import SymbolIcon from "../SymbolIcon.svelte";

  /**
   * The window's notices, as the Mac's BrowserNoticeLayer shows them: one at a
   * time in the top trailing corner of the page, a newer one replacing one
   * still showing, each going by itself once it has been up long enough to
   * read.
   */
  let { shell }: { shell: ShellTransport | null } = $props();

  let notice = $state<ShownNotice | null>(null);
  let next = 0;

  $effect(() => {
    const show = (shown: WindowNotice) => {
      notice = { ...shown, id: ++next };
    };
    const stop = notices.subscribe((event) => {
      if ("shows" in event) show(event.shows);
      else if (notice?.key === event.dismisses) notice = null;
    });
    const transport = shell;
    if (!transport) return stop;
    transport.onNotice = (message, kind) => show({ message, symbol: kind === "link" ? "link" : "checkmark.circle.fill" });
    transport.onUnavailable = (feature) => {
      const [message, symbol] = unavailable[feature] ?? fallback;
      show({ message, symbol });
    };
    return () => {
      stop();
      transport.onNotice = undefined;
      transport.onUnavailable = undefined;
    };
  });

  $effect(() => {
    const shown = notice;
    if (!shown) return;
    const timer = setTimeout(() => {
      if (notice?.id === shown.id) notice = null;
    }, noticeDuration(shown.message));
    return () => clearTimeout(timer);
  });
</script>

<div class="notices" role="status" aria-live="polite">
  {#each notice ? [notice] : [] as shown (shown.id)}
    <div
      class="notice"
      in:presence={{ pose: { opacity: 0, y: -12 }, timing: tokens.feedbackPresentation }}
      out:presence={{ pose: { opacity: 0, y: -12 }, timing: tokens.dismissal }}
    >
      <SymbolIcon name={shown.symbol} size={15} />
      <span aria-label={shown.accessibilityLabel}>{shown.message}</span>
    </div>
  {/each}
</div>
