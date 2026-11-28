<script lang="ts" module>
  import { type Intent, ReorderSpaces, SetSpaceBranding, type SpaceState } from "@crest/contracts";

  import type { Session } from "../boot";
  import { type MenuEntry, spaceMenuIcon } from "../menus";
  import { groupMembers, isDeleting, isSubSpace, type SpaceDeletionRequest } from "../spaces/space-deletion";
  import {
    addSubSpace,
    canJoinGroup,
    joinableGroups,
    joining,
    offersSubSpace,
    primaryOf,
    separating,
    type SpaceGroupChange,
  } from "../spaces/space-groups";
  import { setSpaceLock } from "../spaces/space-access";
  import { startingLook } from "../spaces/space-look";

  /** The tabs of a Space's page, which a Settings tab keeps as its selection moves between Spaces. */
  export type SpacePageTab = "appearance" | "browsing" | "privacy" | "extensions";

  /**
   * The Space's actions in its page's header, as the Mac's menu lists them
   * there: Rename and Edit Crest…, Move Up and Move Down, deleting the Space
   * (or a primary with its Sub-Spaces), then Reset Appearance, back to the
   * look the Space started from while it has moved from it, and Artwork
   * Credits. Lock Space stands before deleting: on, it asks Windows Hello
   * before the Space shows, as the Mac asks for Touch ID or the password; a
   * private window's Spaces can't lock. The group's items stand before it:
   * New Sub-Space, Separate from its primary, and Make Sub-Space of another
   * group, each change after its question.
   */
  function spaceMenu({ session, space, spaces, rename, editCrest, showCredits, requestDeletion, requestGroupChange }: {
    session: Session;
    space: SpaceState;
    spaces: readonly SpaceState[];
    rename: () => void;
    editCrest: () => void;
    showCredits: () => void;
    requestDeletion: (request: SpaceDeletionRequest) => void;
    requestGroupChange: (change: SpaceGroupChange) => void;
  }): MenuEntry[] {
    const reorder = (order: readonly string[] | null) => () => {
      if (order) void send(session, ReorderSpaces({ workspaceId: session.workspaceId, spaceIds: order }));
    };
    const up = movedOrder(spaces, space.id, -1);
    const down = movedOrder(spaces, space.id, 1);
    const starting = startingLook(space.settings.look);
    const resets = starting !== null && JSON.stringify(starting) !== JSON.stringify(space.settings.look);
    return [
      { title: "Rename", icon: "pencil", run: rename },
      { title: "Edit Crest…", icon: "paintpalette", run: editCrest },
      "separator",
      { title: "Move Up", icon: "arrow.up", enabled: up !== null, run: reorder(up) },
      { title: "Move Down", icon: "arrow.down", enabled: down !== null, run: reorder(down) },
      "separator",
      ...groupItems(session, space, spaces, requestGroupChange),
      "separator",
      {
        title: "Lock Space", icon: "lock", checked: space.settings.requiresAuthentication,
        enabled: !(session.core.state.workspaces.get(session.workspaceId)?.kind.isPrivate ?? false),
        run: () => void setSpaceLock(session, space, !space.settings.requiresAuthentication),
      },
      "separator",
      ...deletionItems(session, space, spaces, requestDeletion),
      "separator",
      {
        title: "Reset Appearance", icon: "arrow.counterclockwise", enabled: resets,
        run: () => starting && void send(session, SetSpaceBranding({ workspaceId: session.workspaceId, spaceId: space.id, branding: starting })),
      },
      { title: "Artwork Credits", icon: "info.circle", run: showCredits },
    ];
  }

  /**
   * BrowserSpaceGroupMenuItems: New Sub-Space, which starts one after this
   * Space; Separate from its primary, for a Sub-Space; and Make Sub-Space of,
   * listing every other group by its primary, for a Space that may join one.
   */
  function groupItems(session: Session, space: SpaceState, spaces: readonly SpaceState[],
    request: (change: SpaceGroupChange) => void): MenuEntry[] {
    const items: MenuEntry[] = [];
    const isPrivate = session.core.state.workspaces.get(session.workspaceId)?.kind.isPrivate ?? false;
    if (!isPrivate) items.push({ title: "New Sub-Space", icon: "plus.square.on.square", enabled: offersSubSpace(session, space), run: () => void addSubSpace(session, space.id) });
    const separation = separating(session, space, spaces);
    if (separation) items.push({ title: `Separate from “${primaryOf(space, spaces).settings.name}”…`, icon: "rectangle.portrait.and.arrow.right", run: () => request(separation) });
    const groups = canJoinGroup(session, space, spaces) ? joinableGroups(session, space, spaces) : [];
    if (groups.length > 0) {
      items.push({
        title: "Make Sub-Space of", icon: "square.on.square",
        submenu: groups.map((group) => ({
          title: group.settings.name, icon: spaceMenuIcon(group),
          run: () => {
            const join = joining(session, space, group, spaces);
            if (join) request(join);
          },
        })),
      });
    }
    return items;
  }

  /**
   * BrowserSpaceDeletionMenuItems: Delete, while another Space stays and the
   * Space isn't going already, and for a primary that leads Sub-Spaces,
   * Delete with them, while a Space outside the group stays.
   */
  function deletionItems(session: Session, space: SpaceState, spaces: readonly SpaceState[],
    request: (request: SpaceDeletionRequest) => void): MenuEntry[] {
    const name = space.settings.name;
    const members = groupMembers(space, spaces);
    const leadsGroup = !isSubSpace(space) && members.length > 1;
    return [
      {
        title: `Delete “${name}”…`, icon: "trash", enabled: spaces.length > 1 && !isDeleting(session, space.id),
        run: () => request({ spaceId: space.id, includesSubSpaces: false }),
      },
      ...(leadsGroup ? [{
        title: `Delete “${name}” and Its Sub-Spaces…`, icon: "trash", enabled: members.length < spaces.length,
        run: () => request({ spaceId: space.id, includesSubSpaces: true }),
      }] : []),
    ];
  }

  /**
   * BrowserSpaceOrderActions: the Spaces' order with `spaceId` moved one place
   * by `step`, or null where it can't go. A group moves whole among the
   * groups; a Sub-Space moves within its group, never before its primary.
   */
  export function movedOrder(spaces: readonly SpaceState[], spaceId: string, step: number): string[] | null {
    const groups: string[][] = [];
    for (const candidate of spaces) {
      const primaryId = candidate.membership?.primaryId;
      const group = primaryId && primaryId !== candidate.id ? groups.find((members) => members[0] === primaryId) : undefined;
      if (group) group.push(candidate.id);
      else groups.push([candidate.id]);
    }
    const group = groups.findIndex((members) => members.includes(spaceId));
    if (group < 0) return null;
    const member = groups[group].indexOf(spaceId);
    if (member > 0) {
      const target = member + step;
      if (target <= 0 || target >= groups[group].length) return null;
      [groups[group][member], groups[group][target]] = [groups[group][target], groups[group][member]];
    } else {
      const target = group + step;
      if (target < 0 || target >= groups.length) return null;
      [groups[group], groups[target]] = [groups[target], groups[group]];
    }
    return groups.flat();
  }

  function send(session: Session, intent: Intent) {
    return session.core.send(intent).then(() => true, () => false);
  }

  /** How the sheets' backdrops fade, Motion's own fade for opacity, which the React page took by default. */
  const backdropFade = { duration: 0.3, ease: [0.25, 0.1, 0.35, 1] } as const;
</script>

<script lang="ts">
  import { SetSpaceIdentity } from "@crest/contracts";

  import heraldryCredits from "../../../../../CrestShared/Resources/HeraldicArtworkCredits.txt?raw";
  import { showContextMenu } from "../menus";
  import { presence } from "../motion";
  import { Sheet } from "../shell/prompts/PromptSheet";
  import { deletionPlan, runDeletion } from "../spaces/space-deletion";
  import { applyGroupChange } from "../spaces/space-groups";
  import { failureMessages, isAuthenticating, isLocked, unlockSpace, useAccessFailure } from "../spaces/space-access";
  import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { useCoreVersion } from "../use-core";
  import BrowsingTab from "./BrowsingTab.svelte";
  import { Group, keptScroll, Segmented } from "./controls";
  import DeletionSheet from "./DeletionSheet.svelte";
  import ExtensionsTab from "./ExtensionsTab.svelte";
  import SpacePrivacySections from "./privacy.svelte";
  import { SpaceAppearance } from "./SpaceAppearance";

  /**
   * The Mac's BrowserSettingsSpacePage, as far as Windows has built it: the
   * Space's icon and name, which edits in place, and its actions menu, over
   * its tabs: Appearance,
   * its look (Edit Space… opens it); Browsing, how it searches, archives and
   * shares pinned tabs; Privacy, what it keeps and clearing what it holds;
   * and Extensions.
   */
  let { session, space, spaces, tab, onTab, onOpenSpace, scrolls }: {
    session: Session;
    space: SpaceState;
    spaces: readonly SpaceState[];
    tab: SpacePageTab;
    onTab: (tab: SpacePageTab) => void;
    /** Shows another Space's page in this Settings tab, as a crest of the group row does. */
    onOpenSpace: (spaceId: string) => void;
    /** Where each of the Settings tab's pages was scrolled. */
    scrolls: Map<string, number>;
  } = $props();

  let name = $state.raw<{ spaceId: string; draft: string } | null>(null);
  let nameField: HTMLInputElement | undefined = $state();
  let showsCredits = $state(false);
  let deleting = $state.raw<SpaceDeletionRequest | null>(null);
  const plan = $derived.by(() => {
    const request = deleting;
    return request ? deletionPlan(request, spaces) : null;
  });
  let groupChange = $state.raw<SpaceGroupChange | null>(null);
  const isPrivate = $derived.by(() => (useCoreVersion(session),
    session.core.state.workspaces.get(session.workspaceId)?.kind.isPrivate ?? false));
  const draft = $derived.by(() => {
    const editing = name;
    return editing?.spaceId === space.id ? editing.draft : space.settings.name;
  });
  const locked = $derived.by(() => (useCoreVersion(session), isLocked(session.core, space)));
  const authenticating = $derived.by(() => (useCoreVersion(session), isAuthenticating(session.core, space.id)));
  const anyAuthenticating = $derived.by(() => (useCoreVersion(session), isAuthenticating(session.core)));
  const members = $derived(groupMembers(space, spaces));
  const last = $derived(members.at(-1) ?? space);
  const offersAnother = $derived.by(() => (useCoreVersion(session), offersSubSpace(session, last)));
  const commitName = () => {
    if (!name || name.spaceId !== space.id) return;
    const next = name.draft.trim();
    name = null;
    if (next === space.settings.name) return;
    void session.core.send(SetSpaceIdentity({
      workspaceId: session.workspaceId, spaceId: space.id, name: next, symbol: space.settings.symbol, accent: space.settings.accent,
    })).catch(() => {});
  };

  const requestDeletion = (request: SpaceDeletionRequest) => {
    deleting = request;
  };
  const requestGroupChange = (change: SpaceGroupChange) => {
    groupChange = change;
  };

  /** A crest's menu in the group row: Move Left and Move Right for a Sub-Space, then the group's items and deleting. */
  const crestMenu = (member: SpaceState): MenuEntry[] => {
    const entries: MenuEntry[] = [];
    if (isSubSpace(member)) {
      const left = movedOrder(spaces, member.id, -1);
      const right = movedOrder(spaces, member.id, 1);
      const reorder = (order: readonly string[] | null) => () => {
        if (order) void send(session, ReorderSpaces({ workspaceId: session.workspaceId, spaceIds: order }));
      };
      entries.push({ title: "Move Left", icon: "arrow.left", enabled: left !== null, run: reorder(left) },
        { title: "Move Right", icon: "arrow.right", enabled: right !== null, run: reorder(right) }, "separator");
    }
    return [...entries, ...groupItems(session, member, spaces, requestGroupChange), "separator",
      ...deletionItems(session, member, spaces, requestDeletion)];
  };
</script>

<!--
  BrowserSpaceGroupCrestRow: the Spaces of the group the page edits, as a
  row of crests between the header and the tabs. Choosing a crest opens that
  Space's page, + starts another Sub-Space, and each crest's menu moves it
  within the group (a Sub-Space), moves it to another group, separates it or
  deletes it. A Space on its own shows its one crest and +, which is how its
  first Sub-Space starts, so the row never comes or goes. The Mac's crests
  also drag; here the menu moves them.
-->
{#snippet groupCrestRow()}
  <div class="settings-group-crests" role="group" aria-label="Sub-Spaces" data-testid="space-group-crests">
    <div class="settings-group-well">
      {#each members as member (member.id)}
        <button type="button" class={`settings-group-crest${member.id === space.id ? " selected" : ""}`}
          title={member.settings.name} aria-label={member.settings.name} aria-current={member.id === space.id || undefined}
          data-testid={`space-group-crest-${member.id}`}
          onclick={() => onOpenSpace(member.id)}
          oncontextmenu={(event) => {
            event.preventDefault();
            void showContextMenu({ clientX: event.clientX, clientY: event.clientY }, crestMenu(member));
          }}>
          <SpaceIdentityIcon symbol={member.settings.symbol} branding={member.settings.look} size={20} />
        </button>
      {/each}
    </div>
    <button type="button" class="settings-group-add" title="New Sub-Space" aria-label="New Sub-Space"
      data-testid="space-group-add-sub-space" disabled={!offersAnother}
      onclick={() => void addSubSpace(session, last.id)}>
      <SymbolIcon name="plus" size={13} />
    </button>
  </div>
{/snippet}

<!--
  BrowserSettingsPrivateSpaceAccessSection: a locked Space's page holds only
  the Space and Unlock, under "Locked", until Windows Hello unlocks it.
-->
{#snippet lockedSpaceSection()}
  {@const failure = useAccessFailure(space.id)}
  <div class="settings-scroll">
    <div class="settings-column">
      <Group title="Locked" footer={failure ? failureMessages[failure] : "Unlock this Space to see its settings."}>
        <div class="settings-row settings-locked-row" data-testid="settings-private-space-lock">
          <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={20} />
          <span class="settings-row-title">{space.settings.name}</span>
          <span class="settings-spacer"></span>
          <button type="button" class="settings-unlock" disabled={anyAuthenticating}
            aria-label={authenticating ? "Authenticating…" : `Unlock ${space.settings.name}`}
            data-testid="settings-unlock-space" onclick={() => void unlockSpace(session, space)}>
            <SymbolIcon name="lock.open.fill" size={12} />
            Unlock
          </button>
        </div>
      </Group>
    </div>
  </div>
{/snippet}

<header class="settings-page-header space">
  <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={26} />
  <input bind:this={nameField} class="settings-space-name" value={draft} aria-label="Space name" placeholder="Untitled Space"
    oninput={(event) => (name = { spaceId: space.id, draft: event.currentTarget.value })}
    onfocusout={commitName}
    onkeydown={(event) => {
      if (event.key === "Enter") event.currentTarget.blur();
      if (event.key === "Escape") name = null;
    }} />
  <button type="button" class="settings-space-menu" aria-label="Space actions" title="Space actions"
    data-testid="space-settings-menu" onclick={(event) => {
      const bounds = event.currentTarget.getBoundingClientRect();
      void showContextMenu({ clientX: bounds.left, clientY: bounds.bottom + 4 }, spaceMenu({
        session, space, spaces,
        rename: () => requestAnimationFrame(() => {
          nameField?.focus();
          nameField?.select();
        }),
        editCrest: () => onTab("appearance"),
        showCredits: () => (showsCredits = true),
        requestDeletion,
        requestGroupChange,
      }));
    }}>
    <SymbolIcon name="ellipsis.circle" size={16} />
  </button>
</header>
{#if !isPrivate}
  {@render groupCrestRow()}
{/if}
<!-- A locked Space shows its settings only once it's unlocked, as the Mac's page does. -->
{#if locked}
  {@render lockedSpaceSection()}
{:else}
  <div class="settings-space-tabs">
    <Segmented label="Space settings" value={tab} onChange={onTab}
      choices={[{ value: "appearance", label: "Appearance" }, { value: "browsing", label: "Browsing" }, { value: "privacy", label: "Privacy" },
        { value: "extensions", label: "Extensions" }]} />
  </div>
  {#key `${space.id}:${tab}`}
    <div class="settings-scroll" {...keptScroll(scrolls, `${space.id}:${tab}`)}>
      <div class={`settings-column${tab === "appearance" ? " wide" : ""}`}>
        {#if tab === "appearance"}
          {#key space.id}
            <SpaceAppearance {session} {space} />
          {/key}
        {:else if tab === "browsing"}
          <BrowsingTab {session} {space} {spaces} />
        {:else if tab === "privacy"}
          <SpacePrivacySections {session} {space} {spaces} />
        {:else}
          <ExtensionsTab {session} {space} {spaces} />
        {/if}
      </div>
    </div>
  {/key}
{/if}
{#if showsCredits}
  <div class="sheet-backdrop" in:presence={{ pose: { opacity: 0 }, timing: backdropFade }}
    out:presence={{ pose: { opacity: 0 }, timing: backdropFade }}>
    <Sheet title="Artwork Credits" primary="Done" onPrimary={() => (showsCredits = false)} onEscape={() => (showsCredits = false)}>
      <div class="sheet-credits" data-testid="artwork-credits">{heraldryCredits.trim()}</div>
    </Sheet>
  </div>
{/if}
{#each groupChange ? [groupChange] : [] as change ("group")}
  <div class="sheet-backdrop" in:presence={{ pose: { opacity: 0 }, timing: backdropFade }}
    out:presence={{ pose: { opacity: 0 }, timing: backdropFade }}>
    <Sheet title={change.title} primary={change.confirmation} secondary="Cancel"
      onPrimary={() => {
        groupChange = null;
        // The change redraws much of the window, so the question finishes closing first, as on the Mac.
        setTimeout(() => void applyGroupChange(session, change), 140);
      }}
      onEscape={() => (groupChange = null)}>
      <p class="sheet-message">{change.message}</p>
    </Sheet>
  </div>
{/each}
{#each plan ? [plan] : [] as shown ("delete")}
  <div class="sheet-backdrop" in:presence={{ pose: { opacity: 0 }, timing: backdropFade }}
    out:presence={{ pose: { opacity: 0 }, timing: backdropFade }}>
    <DeletionSheet plan={shown} onCancel={() => (deleting = null)} onDelete={(successor) => {
      deleting = null;
      // The deletion redraws much of the window, so the question finishes closing first, as on the Mac.
      setTimeout(() => void runDeletion(session, shown, spaces, successor), 140);
    }} />
  </div>
{/each}
