<script lang="ts">
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { type BlockedPopupNotice, noticeTitle } from "../blocked-popups";

  /**
   * The Site Controls trigger at the address field's trailing end, as the
   * Mac's BrowserSiteControlTrigger: in the warning tone, with a dot, while the
   * page has a blocked pop-up to tell of.
   */
  let { open, notice, onToggle }: {
    open: boolean;
    notice: BlockedPopupNotice | null;
    onToggle: () => void;
  } = $props();

  const label = $derived(notice ? `${noticeTitle(notice)}. Site Controls` : "Site Controls");
</script>

<button type="button" class={["site-control-trigger", open && "open", notice && "warning"]}
  aria-label={label} title={label} aria-expanded={open} aria-haspopup="dialog" onclick={onToggle}>
  <SymbolIcon name="slider.horizontal.3" size={12} />
  {#if notice}<span class="site-control-dot" aria-hidden="true"></span>{/if}
</button>
