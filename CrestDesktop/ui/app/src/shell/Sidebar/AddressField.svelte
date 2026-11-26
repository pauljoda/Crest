<script lang="ts">
  import { openPalette } from "../../commands";
  import { useFieldHandedOff } from "../../palette/palette-morph";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import type { BlockedPopupNotice } from "../blocked-popups";
  import { AddressSecurityButton, SiteControlTrigger } from "../SiteControl";
  import AddressSwap from "./AddressSwap.svelte";
  import { addressPresentation } from "./sidebar-parts.svelte";

  /**
   * The shown tab's address, which opens the command palette to edit it, as
   * the Mac's sidebar address field does; typing an address happens there.
   * The site shows centred over the rest of its address. A live site puts its
   * lock in the leading slot and Site Controls in the trailing one; a tab
   * holding a page without one shows the lock or the search glyph instead.
   * While the page loads, the Space's accent fills the field from its leading
   * edge, the window's only loading indicator. Showing another Space, its
   * parts pop out and the new Space's pop in, as the Mac's BrowserAddressSwap.
   */
  let { space, address, site, secure, resident, loading, accent, focused = true, activate = () => openPalette("editLocation") }: {
    /** The Space the field shows, whose change swaps its parts. */
    space: string;
    address: string;
    site: {
      readonly secure: boolean;
      readonly certificate: boolean;
      readonly reviewCertificate: () => void;
      readonly open: boolean;
      readonly notice: BlockedPopupNotice | null;
      readonly toggle: () => void;
    } | null;
    secure: boolean;
    /** Whether the shown tab holds a page, which an address alone does not make it. */
    resident: boolean;
    loading: boolean;
    accent: string;
    focused?: boolean;
    activate?: () => void;
  } = $props();

  const shown = $derived(addressPresentation(address));
  // A Space showing only the prompt swaps nothing with another that does.
  const swap = $derived(address ? space : null);
</script>

<!-- The field fades out while the palette that grew out of it is open, keeping its place. -->
<div class={`address-field${focused && useFieldHandedOff() ? " handed-off" : ""}${loading ? " loading" : ""}`} style:--field-accent={accent}>
  <span class="address-progress" aria-hidden="true"></span>
  <AddressSwap {swap} shows={!!site || (resident && !!address)}>
    {#if site}
      <AddressSecurityButton secure={site.secure} certificate={site.certificate} onReview={site.reviewCertificate} />
    {:else}
      <span class="address-glyph" aria-hidden="true">
        <SymbolIcon name={secure ? "lock.fill" : "magnifyingglass"} size={10} strokeWidth={2.5} />
      </span>
    {/if}
  </AddressSwap>
  <button type="button" class="address-summary" aria-label={address ? `Address, ${address}` : "Address and search"}
    {...{ "aria-description": "Opens the command palette" }} onclick={activate}>
    <AddressSwap {swap} shows>
      <span class={`address-domain${address ? "" : " placeholder"}`}>{shown.domain}</span>
      {#if shown.route}
        <span class="address-route">{shown.route}</span>
      {/if}
    </AddressSwap>
  </button>
  <AddressSwap {swap} shows={!!site}>
    {#if site}
      <SiteControlTrigger open={site.open} notice={site.notice} onToggle={site.toggle} />
    {/if}
  </AddressSwap>
</div>
