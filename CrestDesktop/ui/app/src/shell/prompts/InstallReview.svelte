<script lang="ts">
  import { EngineKind, ExtensionCopyDestinations, type ExtensionInstallQuestion, type SpaceState } from "@crest/contracts";
  import { untrack } from "svelte";

  import type { Session } from "../../boot";
  import { type ExtensionReview, extensions } from "../../extensions";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { useCoreVersion } from "../../use-core";
  import { motionDefaults } from "../motion-defaults";
  import { useImageBytes } from "./ExtensionReview.svelte";
  import { Sheet } from "./PromptSheet";

  /** The window's review of one install, as its layer shows it. */
  let { session, spaces, review }: { session: Session; spaces: readonly SpaceState[]; review: ExtensionReview } = $props();

  const install = $derived((useCoreVersion(session), session.core.state.extensionInstalls.get(review.installId)));
  const asked = $derived.by(() => {
    useCoreVersion(session);
    return [...session.core.state.extensionPrompts.values()].find((prompt) => prompt.installId === review.installId) ?? null;
  });
  // The question leaves once the install ends; the review keeps its name and icon to say it is ready.
  let kept = $state.raw<ExtensionInstallQuestion | null>(null);
  $effect(() => {
    if (asked) kept = asked.question;
  });
  const question = $derived(asked?.question ?? null);
  const shown = $derived(question ?? kept);
  const space = $derived(spaces.find((candidate) => candidate.id === review.spaceId));
  const spaceName = $derived(space?.settings.name ?? "Space");
  const stage = $derived(install?.stage);
  const preparing = $derived(!stage || stage.isPreparing);
  const installing = $derived(stage?.isInstalling ?? false);
  const completed = $derived(stage?.name === "installed");
  const failure = $derived(install?.failure ?? null);
  let withhold = $state<boolean | null>(null);
  const withholds = $derived(withhold ?? question?.withholdsSiteAccess ?? false);
  let canAccept = $state(false);
  let accessOpen = $state(true);
  let choosingSpaces = $state(false);
  let destinations = $state.raw<readonly string[]>([]);
  const icon = useImageBytes(() => shown?.icon);
  // Accepting waits a moment after the question appears.
  const promptId = $derived(asked?.promptId ?? null);
  $effect(() => {
    const id = promptId;
    canAccept = false;
    if (!id) return;
    const timer = setTimeout(() => (canAccept = true), 500);
    return () => clearTimeout(timer);
  });
  // The Spaces a copy may go to, as the core answers it.
  const spaceId = $derived(review.spaceId);
  const extensionId = $derived(review.extensionId);
  $effect(() => {
    const destinationsOf = ExtensionCopyDestinations({ spaceId, engine: EngineKind.chromium, extensionId });
    untrack(() => {
      void session.core.query(destinationsOf).then((answer) => (destinations = answer.spaceIds), () => (destinations = []));
    });
  });
  // An install whose Space went out of reach closes its review.
  $effect(() => {
    if (failure?.closesReview) untrack(() => extensions.dismiss(session));
  });
  const dismiss = () => {
    if (!installing) extensions.dismiss(session);
  };
  const accept = () => {
    if (!completed && promptId && canAccept && !installing && !failure) extensions.accept(session, promptId, withholds);
  };
  const title = $derived(completed ? "Extension Installed" : shown?.name ?? "Install Extension");
  const copies = $derived(review.copySpaceIds);
</script>

{#if choosingSpaces}
  <!-- The chooser goes at once as the review comes back, and the review at once as the chooser comes. -->
  {#key review.installId}
    <Sheet title="Install in Other Spaces" primary="Done" onPrimary={() => (choosingSpaces = false)}
      onEscape={() => (choosingSpaces = false)}>
      <p class="sheet-message">{question?.name ?? "The extension"} installs in {spaceName} and each Space chosen here.</p>
      <div class="extension-spaces" role="group" aria-label="Other Spaces">
        {#if destinations.length === 0}<p class="sheet-message">No other Space can take a copy.</p>{/if}
        {#each destinations as destinationId (destinationId)}
          {@const destination = spaces.find((candidate) => candidate.id === destinationId)}
          {@const checked = copies.includes(destinationId)}
          <label class="extension-space">
            <input type="checkbox" {checked}
              onchange={() => extensions.chooseCopies(checked ? copies.filter((id) => id !== destinationId) : [...copies, destinationId])} />
            {destination?.settings.name ?? "Space"}
          </label>
        {/each}
      </div>
    </Sheet>
  {/key}
{:else}
  <!-- svelte-ignore a11y_interactive_supports_focus -->
  <div class="sheet extension-review" role="dialog" aria-modal="true" aria-label={title}
    in:motionDefaults|global={{ pose: { opacity: 0, scale: 1.04 } }}
    out:motionDefaults|global={{ pose: { opacity: 0, scale: 0.98 }, going: true, instant: choosingSpaces }}
    onkeydown={(event) => {
      if (event.key === "Escape") {
        event.preventDefault();
        dismiss();
      }
    }}>
    <div class="sheet-body">
      <div class="extension-review-header">
        <span class="extension-icon large">
          {#if icon.current}<img src={icon.current} alt="" />{:else}<SymbolIcon name="puzzlepiece.extension" size={22} />{/if}
        </span>
        <div>
          <h2 class="sheet-title">{title}</h2>
          {#if shown && !completed}
            <span class="extension-verified"><SymbolIcon name="checkmark.seal.fill" size={12} /> Verified Chrome Web Store package</span>
          {/if}
        </div>
      </div>
      {#if preparing && !failure}
        {#if review.downloaded !== null && review.downloaded < 1}
          <div class="extension-progress" role="progressbar" aria-valuenow={Math.round(review.downloaded * 100)} aria-valuemin={0}
            aria-valuemax={100}>
            <span>Downloading extension…</span>
            <span class="extension-progress-track"><span style:width="{review.downloaded * 100}%"></span></span>
          </div>
        {:else}
          <p class="sheet-message extension-preparing"><span class="extension-spinner" aria-hidden="true"></span> Preparing extension…</p>
        {/if}
      {:else if completed}
        <p class="extension-ready"><SymbolIcon name="checkmark.circle.fill" size={14} /> {shown?.name ?? "The extension"} is ready in {spaceName}.</p>
        {#if (install?.installedCount ?? 0) > 1}
          <p class="sheet-message">Installed in {install!.installedCount - 1} additional Spaces.</p>
        {/if}
      {:else if question}
        <fieldset class="extension-question" disabled={installing}>
          {#if question.summary}<p class="sheet-message">{question.summary}</p>{/if}
          <dl class="extension-facts">
            <dt>Install In</dt><dd>{spaceName} Space</dd>
            <dt>Version</dt><dd>{question.version}</dd>
          </dl>
          <p class="extension-caution">Only install extensions you trust. Review the access below before installing.</p>
          <button type="button" class="extension-disclosure" aria-expanded={accessOpen} onclick={() => (accessOpen = !accessOpen)}>
            <SymbolIcon name={accessOpen ? "chevron.down" : "chevron.right"} size={10} />
            <SymbolIcon name="hand.raised.fill" size={12} />
            Review Access and Compatibility
          </button>
          {#if accessOpen}
            <div class="extension-access">
              <strong>Permissions and Website Access</strong>
              {#if question.permissions.length === 0}
                <span class="sheet-message">No additional browser permissions requested.</span>
              {:else}
                <ul>
                  {#each question.permissions as permission, index (index)}<li>{permission}</li>{/each}
                </ul>
              {/if}
              {#if question.canWithholdSiteAccess}
                <label class="extension-withhold">
                  <input type="checkbox" checked={withholds} onchange={(event) => (withhold = event.currentTarget.checked)} />
                  Withhold website access until I grant it
                </label>
              {/if}
            </div>
          {/if}
          <div class="extension-other-spaces">
            <button type="button" class="sheet-button" onclick={() => (choosingSpaces = true)}>Install in other Spaces…</button>
            {#if copies.length > 0}<span class="extension-caution">Additional Spaces: {copies.length}</span>{/if}
          </div>
        </fieldset>
      {/if}
      {#if failure}
        <p class="extension-failure"><SymbolIcon name="exclamationmark.triangle.fill" size={13} /> {failure.message}</p>
        {#if (install?.installedCount ?? 0) > 0}
          <p class="extension-caution">Installed in {install!.installedCount} Spaces before this error.</p>
        {/if}
      {/if}
    </div>
    <div class="sheet-actions">
      {#if completed}
        <button type="button" class="sheet-button primary" data-autofocus onclick={() => extensions.dismiss(session)}>Done</button>
      {:else}
        <button type="button" class="sheet-button" disabled={installing} onclick={dismiss}>Cancel</button>
        {#if question && !failure}
          <button type="button" class="sheet-button primary" disabled={!canAccept || installing} onclick={accept}>
            {installing ? "Adding…" : "Add Extension"}
          </button>
        {/if}
      {/if}
    </div>
  </div>
{/if}
