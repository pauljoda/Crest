<script lang="ts">
  import SymbolIcon from "../../SymbolIcon.svelte";

  /**
   * The lock a live site puts in the address field's leading slot, as the
   * Mac's BrowserAddressSecurityButton: it shows whether the connection is
   * secure and, where the page has a certificate, opens it.
   */
  let { secure, certificate, onReview }: {
    secure: boolean;
    certificate: boolean;
    onReview: () => void;
  } = $props();

  const description = $derived(!secure ? "Connection Not Secure" : certificate ? "Review Certificate" : "Connection Secure");
</script>

<button type="button" class={["address-security", !secure && "insecure"]} disabled={!certificate}
  aria-label={description} title={description} onclick={onReview}>
  <SymbolIcon name={secure ? "lock.fill" : "lock.open.fill"} size={12} />
</button>
