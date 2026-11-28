<script lang="ts" module>
  import { ExtensionIcons } from "@crest/contracts";
  import { untrack } from "svelte";

  import type { Session } from "../boot";
  import { extensions } from "../extensions";
  import { reader } from "../reactive";

  /** How a `motion.div` without a transition of its own faded: Motion's 0.3 s on its gentler ease. */
  const fade = { duration: 0.3, ease: [0.25, 0.1, 0.35, 1] } as const;

  /** The extensions store's version, followed by the expression that reads it. */
  const extensionsVersion = reader((listener) => extensions.subscribe(listener), () => extensions.version);

  /** Each extension's icon in a profile, as the engine draws them, by extension. */
  function useExtensionIcons(session: () => Session, profileId: () => string, revision: () => unknown): {
    readonly current: ReadonlyMap<string, string>;
  } {
    let icons = $state.raw<ReadonlyMap<string, string>>(new Map());
    $effect(() => {
      const core = session().core;
      const profile = profileId();
      void revision();
      return untrack(() => {
        let current = true;
        const made: string[] = [];
        void core.request(ExtensionIcons({ profileId: profile })).then((list) => {
          if (!current) return;
          const next = new Map<string, string>();
          for (const icon of list.icons) {
            if (!icon.image || icon.image.length === 0) continue;
            const url = URL.createObjectURL(new Blob([icon.image as BlobPart]));
            made.push(url);
            next.set(icon.extensionId, url);
          }
          icons = next;
        }, () => {});
        return () => {
          current = false;
          for (const url of made) URL.revokeObjectURL(url);
        };
      });
    });
    return {
      get current() {
        return icons;
      },
    };
  }
</script>

<script lang="ts">
  import { EngineKind, ExtensionChange, type InstalledExtension, ListExtensions, type SpaceState } from "@crest/contracts";
  import { CoreRejection } from "@crest/core-client";

  import { change, extensionPages, openExtensionPage } from "../extensions";
  import { presence } from "../motion";
  import { Sheet } from "../shell/prompts/PromptSheet";
  import { useCoreVersion } from "../use-core";
  import { Button, Group, Row } from "./controls";
  import ExtensionCopySheet from "./ExtensionCopySheet.svelte";
  import ExtensionRow from "./ExtensionRow.svelte";
  import { groupOf } from "./privacy.svelte";

  /**
   * The Mac's BrowserExtensionsView, a Space's Extensions: the extensions its
   * profile runs, each with its switch, what it may access, its settings and
   * removal, and copies in other Spaces; then where to add more.
   */
  let { session, space, spaces }: { session: Session; space: SpaceState; spaces: readonly SpaceState[] } = $props();

  const revision = $derived((extensionsVersion(), extensions.revision));
  let refusal = $state<string | null>(null);
  // The engine lists the profile's extensions again whenever they change; only the latest request's refusal is said.
  $effect(() => {
    const spaceId = space.id;
    void revision;
    let current = true;
    untrack(() => {
      refusal = null;
      session.core.send(ListExtensions({ spaceId, engine: EngineKind.chromium })).catch((error: unknown) => {
        if (!current) return;
        const kind = error instanceof CoreRejection ? error.rejection.$kind : null;
        refusal = kind === "SpaceIsPrivate" ? "Private windows don’t run extensions."
          : kind === "SpaceLocked" ? "Unlock this Space to see its extensions." : "Couldn’t list this Space’s extensions.";
      });
    });
    return () => {
      current = false;
    };
  });
  const listed = $derived((useCoreVersion(session), session.core.state.installedExtensions.get(space.profileId) ?? null));
  const icons = useExtensionIcons(() => session, () => space.profileId, () => listed);
  const installed = $derived([...(listed ?? [])].sort((left, right) => left.name.localeCompare(right.name, undefined, { sensitivity: "base" })));
  const group = $derived(groupOf(space, spaces));
  const shared = $derived(group.members.length > 1);
  let removing = $state.raw<InstalledExtension | null>(null);
  let copying = $state.raw<InstalledExtension | null>(null);
  const open = (address: string) => openExtensionPage(session, space, address);
</script>

<Group title="Installed">
  {#if refusal}
    <Row>{#snippet title()}<span class="settings-secondary-text">{refusal}</span>{/snippet}</Row>
  {:else if listed === null}
    <div class="settings-row settings-progress-row"><span class="settings-progress" role="progressbar" aria-label="Loading"></span></div>
  {:else if installed.length === 0}
    <Row>{#snippet title()}<span class="settings-secondary-text">No extensions</span>{/snippet}</Row>
  {:else}
    {#each installed as item (item.id)}
      <ExtensionRow {item} icon={icons.current.get(item.id) ?? null}
        setEnabled={(on) => void change(session, space.id, item.id, on ? ExtensionChange.Enable : ExtensionChange.Disable)}
        options={() => item.optionsUrl && open(item.optionsUrl)}
        manage={() => open(extensionPages.details(item.id))}
        remove={() => (removing = item)}
        copy={() => (copying = item)} />
    {/each}
  {/if}
</Group>
<Group title="Add extensions">
  <div class="settings-row settings-buttons-row">
    <Button onClick={() => open(extensionPages.store())}>Open Chrome Web Store</Button>
    <Button onClick={() => open(extensionPages.manage())}>Chromium Extension Manager</Button>
    <span class="settings-spacer"></span>
    <Button onClick={() => open(extensionPages.shortcuts())}>Shortcuts…</Button>
  </div>
</Group>
{#if shared}<p class="settings-footer">Shared by {group.primary.settings.name}’s Sub-Spaces.</p>{/if}
{#if removing}
  {@const asked = removing}
  <div class="sheet-backdrop" in:presence={{ pose: { opacity: 0 }, timing: fade }} out:presence={{ pose: { opacity: 0 }, timing: fade }}>
    <Sheet title="Remove Extension?" primary={`Remove from ${space.settings.name}`} secondary="Cancel" warning
      onPrimary={() => {
        void change(session, space.id, asked.id, ExtensionChange.Remove);
        removing = null;
      }}
      onEscape={() => (removing = null)}>
      <p class="sheet-message">
        {shared ? `${asked.name} and its data are removed from every Space in this group.`
          : `${asked.name} and its data are removed from this Space only.`}
      </p>
    </Sheet>
  </div>
{/if}
{#if copying}
  {@const item = copying}
  <div class="sheet-backdrop" in:presence={{ pose: { opacity: 0 }, timing: fade }} out:presence={{ pose: { opacity: 0 }, timing: fade }}>
    <ExtensionCopySheet {session} {space} {spaces} {item} onDone={() => (copying = null)} />
  </div>
{/if}
