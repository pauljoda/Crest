import {
  CleanUpCurrentTabs,
  CurrentTabCleanup,
  type Intent,
  ReorderSpaces,
  SetBrowsingPreferences,
  SetSeparatePinnedTabs,
  SetSpaceBranding,
  SetSpaceIdentity,
  SetSpaceSearch,
  type SpaceState,
} from "@crest/contracts";
import { AnimatePresence, motion } from "motion/react";
import { useRef, useState } from "react";

import heraldryCredits from "../../../../../CrestShared/Resources/HeraldicArtworkCredits.txt?raw";
import type { Session } from "../boot";
import { type MenuEntry, showContextMenu } from "../menus";
import { Sheet } from "../shell/prompts/PromptSheet";
import {
  deletionPlan,
  groupMembers,
  isDeleting,
  isSubSpace,
  runDeletion,
  type SpaceDeletionPlan,
  type SpaceDeletionRequest,
} from "../spaces/space-deletion";
import {
  addSubSpace,
  applyGroupChange,
  canJoinGroup,
  joinableGroups,
  joining,
  offersSubSpace,
  primaryOf,
  separating,
  type SpaceGroupChange,
} from "../spaces/space-groups";
import { failureMessages, isAuthenticating, isLocked, setSpaceLock, unlockSpace, useAccessFailure } from "../spaces/space-access";
import { startingLook } from "../spaces/space-look";
import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
import { Symbol } from "../symbols";
import { Button, Group, keptScroll, Picker, Row, Segmented, Toggle } from "./controls";
import { ExtensionsTab } from "./ExtensionsTab";
import { SpaceAppearance } from "./SpaceAppearance";
import { groupOf, SpacePrivacySections } from "./privacy";

/** The tabs of a Space's page, which a Settings tab keeps as its selection moves between Spaces. */
export type SpacePageTab = "appearance" | "browsing" | "privacy" | "extensions";

/**
 * The Mac's BrowserSettingsSpacePage, as far as Windows has built it: the
 * Space's icon and name, which edits in place, and its actions menu, over
 * its tabs: Appearance,
 * its look (Edit Space… opens it); Browsing, how it searches, archives and
 * shares pinned tabs; Privacy, what it keeps and clearing what it holds;
 * and Extensions.
 */
export function SpacePage({ session, space, spaces, tab, onTab, onOpenSpace, scrolls }: {
  session: Session;
  space: SpaceState;
  spaces: readonly SpaceState[];
  tab: SpacePageTab;
  onTab: (tab: SpacePageTab) => void;
  /** Shows another Space's page in this Settings tab, as a crest of the group row does. */
  onOpenSpace: (spaceId: string) => void;
  /** Where each of the Settings tab's pages was scrolled. */
  scrolls: Map<string, number>;
}) {
  const [name, setName] = useState<{ spaceId: string; draft: string } | null>(null);
  const nameField = useRef<HTMLInputElement>(null);
  const [showsCredits, setShowsCredits] = useState(false);
  const [deleting, setDeleting] = useState<SpaceDeletionRequest | null>(null);
  const plan = deleting ? deletionPlan(deleting, spaces) : null;
  const [groupChange, setGroupChange] = useState<SpaceGroupChange | null>(null);
  const isPrivate = session.core.state.workspaces.get(session.workspaceId)?.kind.isPrivate ?? false;
  const draft = name?.spaceId === space.id ? name.draft : space.settings.name;
  const commitName = () => {
    if (!name || name.spaceId !== space.id) return;
    const next = name.draft.trim();
    setName(null);
    if (next === space.settings.name) return;
    void session.core.send(SetSpaceIdentity({
      workspaceId: session.workspaceId, spaceId: space.id, name: next, symbol: space.settings.symbol, accent: space.settings.accent,
    })).catch(() => {});
  };
  return (
    <>
      <header className="settings-page-header space">
        <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={26} />
        <input ref={nameField} className="settings-space-name" value={draft} aria-label="Space name" placeholder="Untitled Space"
          onChange={(event) => setName({ spaceId: space.id, draft: event.target.value })}
          onBlur={commitName}
          onKeyDown={(event) => {
            if (event.key === "Enter") event.currentTarget.blur();
            if (event.key === "Escape") setName(null);
          }} />
        <button type="button" className="settings-space-menu" aria-label="Space actions" title="Space actions"
          data-testid="space-settings-menu" onClick={(event) => {
            const bounds = event.currentTarget.getBoundingClientRect();
            void showContextMenu(session.shell, { clientX: bounds.left, clientY: bounds.bottom + 4 }, spaceMenu({
              session, space, spaces,
              rename: () => requestAnimationFrame(() => {
                nameField.current?.focus();
                nameField.current?.select();
              }),
              editCrest: () => onTab("appearance"),
              showCredits: () => setShowsCredits(true),
              requestDeletion: setDeleting,
              requestGroupChange: setGroupChange,
            }));
          }}>
          <Symbol name="ellipsis.circle" size={16} />
        </button>
      </header>
      {!isPrivate && (
        <GroupCrestRow session={session} space={space} spaces={spaces} onOpenSpace={onOpenSpace}
          requestGroupChange={setGroupChange} requestDeletion={setDeleting} />
      )}
      {/* A locked Space shows its settings only once it's unlocked, as the Mac's page does. */}
      {isLocked(session.core, space) ? <LockedSpaceSection session={session} space={space} /> : <>
      <div className="settings-space-tabs">
        <Segmented label="Space settings" value={tab} onChange={onTab}
          choices={[{ value: "appearance", label: "Appearance" }, { value: "browsing", label: "Browsing" }, { value: "privacy", label: "Privacy" },
            { value: "extensions", label: "Extensions" }]} />
      </div>
      <div key={`${space.id}:${tab}`} className="settings-scroll" {...keptScroll(scrolls, `${space.id}:${tab}`)}>
        <div className={`settings-column${tab === "appearance" ? " wide" : ""}`}>
          {tab === "appearance" ? <SpaceAppearance key={space.id} session={session} space={space} />
            : tab === "browsing" ? <BrowsingTab session={session} space={space} spaces={spaces} />
            : tab === "privacy" ? <SpacePrivacySections session={session} space={space} spaces={spaces} />
              : <ExtensionsTab session={session} space={space} spaces={spaces} />}
        </div>
      </div>
      </>}
      <AnimatePresence>
        {showsCredits && (
          <motion.div key="credits" className="sheet-backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <Sheet title="Artwork Credits" primary="Done" onPrimary={() => setShowsCredits(false)} onEscape={() => setShowsCredits(false)}>
              <div className="sheet-credits" data-testid="artwork-credits">{heraldryCredits.trim()}</div>
            </Sheet>
          </motion.div>
        )}
        {groupChange && (
          <motion.div key="group" className="sheet-backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <Sheet title={groupChange.title} primary={groupChange.confirmation} secondary="Cancel"
              onPrimary={() => {
                const change = groupChange;
                setGroupChange(null);
                // The change redraws much of the window, so the question finishes closing first, as on the Mac.
                setTimeout(() => void applyGroupChange(session, change), 140);
              }}
              onEscape={() => setGroupChange(null)}>
              <p className="sheet-message">{groupChange.message}</p>
            </Sheet>
          </motion.div>
        )}
        {plan && (
          <motion.div key="delete" className="sheet-backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <DeletionSheet plan={plan} onCancel={() => setDeleting(null)} onDelete={(successor) => {
              setDeleting(null);
              // The deletion redraws much of the window, so the question finishes closing first, as on the Mac.
              setTimeout(() => void runDeletion(session, plan, spaces, successor), 140);
            }} />
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}

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
    { title: "Rename", run: rename },
    { title: "Edit Crest…", run: editCrest },
    "separator",
    { title: "Move Up", enabled: up !== null, run: reorder(up) },
    { title: "Move Down", enabled: down !== null, run: reorder(down) },
    "separator",
    ...groupItems(session, space, spaces, requestGroupChange),
    "separator",
    {
      title: "Lock Space", checked: space.settings.requiresAuthentication,
      enabled: !(session.core.state.workspaces.get(session.workspaceId)?.kind.isPrivate ?? false),
      run: () => void setSpaceLock(session, space, !space.settings.requiresAuthentication),
    },
    "separator",
    ...deletionItems(session, space, spaces, requestDeletion),
    "separator",
    {
      title: "Reset Appearance", enabled: resets,
      run: () => starting && void send(session, SetSpaceBranding({ workspaceId: session.workspaceId, spaceId: space.id, branding: starting })),
    },
    { title: "Artwork Credits", run: showCredits },
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
  if (!isPrivate) items.push({ title: "New Sub-Space", enabled: offersSubSpace(session, space), run: () => void addSubSpace(session, space.id) });
  const separation = separating(session, space, spaces);
  if (separation) items.push({ title: `Separate from “${primaryOf(space, spaces).settings.name}”…`, run: () => request(separation) });
  const groups = canJoinGroup(session, space, spaces) ? joinableGroups(session, space, spaces) : [];
  if (groups.length > 0) {
    items.push({
      title: "Make Sub-Space of",
      submenu: groups.map((group) => ({
        title: group.settings.name,
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
 * BrowserSpaceGroupCrestRow: the Spaces of the group the page edits, as a
 * row of crests between the header and the tabs. Choosing a crest opens that
 * Space's page, + starts another Sub-Space, and each crest's menu moves it
 * within the group (a Sub-Space), moves it to another group, separates it or
 * deletes it. A Space on its own shows its one crest and +, which is how its
 * first Sub-Space starts, so the row never comes or goes. The Mac's crests
 * also drag; here the menu moves them.
 */
function GroupCrestRow({ session, space, spaces, onOpenSpace, requestGroupChange, requestDeletion }: {
  session: Session;
  space: SpaceState;
  spaces: readonly SpaceState[];
  onOpenSpace: (spaceId: string) => void;
  requestGroupChange: (change: SpaceGroupChange) => void;
  requestDeletion: (request: SpaceDeletionRequest) => void;
}) {
  const members = groupMembers(space, spaces);
  const last = members.at(-1) ?? space;
  const menu = (member: SpaceState): MenuEntry[] => {
    const entries: MenuEntry[] = [];
    if (isSubSpace(member)) {
      const left = movedOrder(spaces, member.id, -1);
      const right = movedOrder(spaces, member.id, 1);
      const reorder = (order: readonly string[] | null) => () => {
        if (order) void send(session, ReorderSpaces({ workspaceId: session.workspaceId, spaceIds: order }));
      };
      entries.push({ title: "Move Left", enabled: left !== null, run: reorder(left) },
        { title: "Move Right", enabled: right !== null, run: reorder(right) }, "separator");
    }
    return [...entries, ...groupItems(session, member, spaces, requestGroupChange), "separator",
      ...deletionItems(session, member, spaces, requestDeletion)];
  };
  return (
    <div className="settings-group-crests" role="group" aria-label="Sub-Spaces" data-testid="space-group-crests">
      <div className="settings-group-well">
        {members.map((member) => (
          <button key={member.id} type="button" className={`settings-group-crest${member.id === space.id ? " selected" : ""}`}
            title={member.settings.name} aria-label={member.settings.name} aria-current={member.id === space.id || undefined}
            data-testid={`space-group-crest-${member.id}`}
            onClick={() => onOpenSpace(member.id)}
            onContextMenu={(event) => {
              event.preventDefault();
              void showContextMenu(session.shell, { clientX: event.clientX, clientY: event.clientY }, menu(member));
            }}>
            <SpaceIdentityIcon symbol={member.settings.symbol} branding={member.settings.look} size={20} />
          </button>
        ))}
      </div>
      <button type="button" className="settings-group-add" title="New Sub-Space" aria-label="New Sub-Space"
        data-testid="space-group-add-sub-space" disabled={!offersSubSpace(session, last)} onClick={() => void addSubSpace(session, last.id)}>
        <Symbol name="plus" size={13} />
      </button>
    </div>
  );
}

/**
 * BrowserSettingsPrivateSpaceAccessSection: a locked Space's page holds only
 * the Space and Unlock, under "Locked", until Windows Hello unlocks it.
 */
function LockedSpaceSection({ session, space }: { session: Session; space: SpaceState }) {
  const failure = useAccessFailure();
  const authenticating = isAuthenticating(session.core, space.id);
  return (
    <div className="settings-scroll">
      <div className="settings-column">
        <Group title="Locked" footer={failure ? failureMessages[failure] : "Unlock this Space to see its settings."}>
          <div className="settings-row settings-locked-row" data-testid="settings-private-space-lock">
            <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={20} />
            <span className="settings-row-title">{space.settings.name}</span>
            <span className="settings-spacer" />
            <button type="button" className="settings-unlock" disabled={isAuthenticating(session.core)}
              aria-label={authenticating ? "Authenticating…" : `Unlock ${space.settings.name}`}
              data-testid="settings-unlock-space" onClick={() => void unlockSpace(session, space)}>
              <Symbol name="lock.open.fill" size={12} />
              Unlock
            </button>
          </div>
        </Group>
      </div>
    </div>
  );
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
      title: `Delete “${name}”…`, enabled: spaces.length > 1 && !isDeleting(session, space.id),
      run: () => request({ spaceId: space.id, includesSubSpaces: false }),
    },
    ...(leadsGroup ? [{
      title: `Delete “${name}” and Its Sub-Spaces…`, enabled: members.length < spaces.length,
      run: () => request({ spaceId: space.id, includesSubSpaces: true }),
    }] : []),
  ];
}

/**
 * The deletion's question, as the Mac's alert asks it, and for a primary
 * that goes alone, its sheet's choice of the Sub-Space that keeps the group.
 */
function DeletionSheet({ plan, onCancel, onDelete }: {
  plan: SpaceDeletionPlan;
  onCancel: () => void;
  onDelete: (successor: string | null) => void;
}) {
  const [successor, setSuccessor] = useState(plan.successors[0]?.id ?? null);
  return (
    <Sheet title={plan.title} primary={plan.confirmation} secondary="Cancel" warning destructive
      onPrimary={() => onDelete(successor)} onEscape={onCancel}>
      <p className="sheet-message">{plan.message}</p>
      {plan.successors.length > 0 && (
        <select className="sheet-field sheet-choice" aria-label="New primary" data-testid="space-deletion-successor"
          value={successor ?? ""} onChange={(event) => setSuccessor(event.target.value)} data-autofocus>
          {plan.successors.map((candidate) => <option key={candidate.id} value={candidate.id}>{candidate.settings.name}</option>)}
        </select>
      )}
    </Sheet>
  );
}

/**
 * BrowserSpaceOrderActions: the Spaces' order with `spaceId` moved one place
 * by `step`, or null where it can't go. A group moves whole among the
 * groups; a Sub-Space moves within its group, never before its primary.
 */
function movedOrder(spaces: readonly SpaceState[], spaceId: string, step: number): string[] | null {
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

/** BrowserSpaceBrowsingSection, with the group's shared pins and Archive Now. */
function BrowsingTab({ session, space, spaces }: { session: Session; space: SpaceState; spaces: readonly SpaceState[] }) {
  const preferences = space.settings.browsingPreferences;
  const catalog = session.core.state.search;
  const providers = catalog?.providers ?? [];
  const chosen = preferences.followsDefaultSearch ? "default"
    : providers.find((provider) => (preferences.selectedCustomEngineId
      ? provider.customId === preferences.selectedCustomEngineId : provider.builtIn === preferences.selectedBuiltInEngine))?.name ?? "default";
  const suggestions = preferences.followsDefaultSuggestions ? "default" : preferences.searchSuggestionsEnabled ? "on" : "off";
  const defaultSuggestions = catalog?.catalog.suggestionsEnabled ? "On" : "Off";
  const setSearch = (provider: string, suggestion: string) => void send(session, SetSpaceSearch({
    workspaceId: session.workspaceId, spaceId: space.id,
    provider: provider === "default" ? null : providers.find((candidate) => candidate.name === provider) ?? null,
    suggestionsEnabled: suggestion === "default" ? null : suggestion === "on",
  }));
  const setBrowsing = (change: Partial<{ currentTabCleanup: typeof preferences.currentTabCleanup }>) =>
    void send(session, SetBrowsingPreferences({
      workspaceId: session.workspaceId, spaceId: space.id, currentTabCleanup: change.currentTabCleanup ?? preferences.currentTabCleanup,
      contentBlocking: preferences.contentBlocking, dataRetention: preferences.dataRetention,
    }));
  const group = groupOf(space, spaces);
  return (
    <>
      <Group title="Browsing" footer="Search suggestions send what you type to the search engine.">
        <Picker title="Search with" value={chosen}
          choices={[{ value: "default", label: `Default (${catalog?.default.title ?? "Search"})` }, ...providers.map((provider) => ({ value: provider.name, label: provider.title }))]}
          onChange={(provider) => setSearch(provider, suggestions)} />
        <Picker title="Search suggestions" value={suggestions}
          choices={[{ value: "default", label: `Default (${defaultSuggestions})` }, { value: "on", label: "On" }, { value: "off", label: "Off" }]}
          onChange={(suggestion) => setSearch(chosen, suggestion)} />
        <Picker title="Archive current tabs" value={preferences.currentTabCleanup} defaultValue={CurrentTabCleanup.after12Hours}
          choices={CurrentTabCleanup.all.map((value) => ({ value, label: value.title }))}
          onChange={(currentTabCleanup) => setBrowsing({ currentTabCleanup })} />
        <Row title="Archive current tabs now">
          <Button onClick={() => void send(session, CleanUpCurrentTabs({ workspaceId: session.workspaceId, spaceId: space.id }))}>Archive Now</Button>
        </Row>
      </Group>
      {group.members.length > 1 && (
        <Group footer={space.settings.separatesPinnedTabs
          ? `Each Space of ${group.primary.settings.name}’s group shows its own pinned tabs.`
          : `Every Space of ${group.primary.settings.name}’s group shows ${group.primary.settings.name}’s pinned tabs.`}>
          <Toggle title="Separate Pinned Tabs" checked={space.settings.separatesPinnedTabs}
            onChange={(separates) => void send(session, SetSeparatePinnedTabs({ workspaceId: session.workspaceId, spaceId: space.id, separates }))} />
        </Group>
      )}
    </>
  );
}
