<script lang="ts" module>
  import { extensions } from "../../extensions";
  import { reader } from "../../reactive";

  /**
   * An image the engine handed over as bytes, as an address the page can show
   * while it is shown: `useImageBytes(() => bytes).current`. Call during a
   * component's initialization.
   */
  export function useImageBytes(bytes: () => Uint8Array | null | undefined): { readonly current: string | null } {
    const url = $derived.by(() => {
      const image = bytes();
      return image && image.length > 0 ? URL.createObjectURL(new Blob([image as BlobPart])) : null;
    });
    $effect(() => {
      const shown = url;
      return () => {
        if (shown) URL.revokeObjectURL(shown);
      };
    });
    return {
      get current() {
        return url;
      },
    };
  }

  /** The extensions store's version, followed by the expression that reads it. */
  const extensionsVersion = reader((listener) => extensions.subscribe(listener), () => extensions.version);
</script>

<script lang="ts">
  import type { SpaceState } from "@crest/contracts";

  import type { Session } from "../../boot";
  import { presence } from "../../motion";
  import { useCoreVersion } from "../../use-core";
  import { motionFade } from "../motion-defaults";
  import InstallReview from "./InstallReview.svelte";
  import { Sheet } from "./PromptSheet";

  /**
   * The Mac's BrowserChromeWebStoreInstallView, as a dialog over the window: the
   * extension's icon and name, the package downloading and being prepared,
   * then the core's question, what it may access, where it installs and in
   * which other Spaces, and Add Extension, which waits a moment so a click
   * meant for something else doesn't land on it; then that it is ready, or why
   * it failed.
   */
  let { session, spaces }: { session: Session; spaces: readonly SpaceState[] } = $props();

  const review = $derived((extensionsVersion(), extensions.review));
  const removal = $derived((extensionsVersion(), extensions.removal));
  const removalName = (extensionId: string) => {
    useCoreVersion(session);
    return [...session.core.state.installedExtensions.values()].flat().find((item) => item.id === extensionId)?.name ?? "This extension";
  };
</script>

<div class="window-dialog-layer">
  {#each review ? [review] : [] as shownReview (shownReview.installId)}
    <div class="sheet-backdrop" in:presence|global={{ pose: { opacity: 0 }, timing: motionFade }}
      out:presence={{ pose: { opacity: 0 }, timing: motionFade }}>
      <InstallReview {session} {spaces} review={shownReview} />
    </div>
  {/each}
  {#each removal && !review ? [removal] : [] as shownRemoval ("removal")}
    {@const spaceName = spaces.find((space) => space.id === shownRemoval.spaceId)?.settings.name ?? "Space"}
    <div class="sheet-backdrop" in:presence|global={{ pose: { opacity: 0 }, timing: motionFade }}
      out:presence={{ pose: { opacity: 0 }, timing: motionFade }}>
      <Sheet title="Remove Extension?" primary="Remove from {spaceName}" secondary="Cancel" warning
        onPrimary={() => extensions.settleRemoval(session, true)} onEscape={() => extensions.settleRemoval(session, false)}>
        <p class="sheet-message">{removalName(shownRemoval.extensionId)} and its data are removed from this Space.</p>
      </Sheet>
    </div>
  {/each}
</div>
