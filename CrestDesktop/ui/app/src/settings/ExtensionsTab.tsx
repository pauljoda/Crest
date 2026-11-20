import {
  EngineKind,
  ExtensionChange,
  ExtensionCopyDestinations,
  ExtensionIcons,
  type InstalledExtension,
  ListExtensions,
  type SpaceState,
} from "@crest/contracts";
import { CoreRejection } from "@crest/core-client";
import { AnimatePresence, motion } from "motion/react";
import { useEffect, useState, useSyncExternalStore } from "react";

import type { Session } from "../boot";
import { change, extensionPages, extensions, openExtensionPage } from "../extensions";
import { Sheet } from "../shell/prompts/PromptSheet";
import { Symbol } from "../symbols";
import { useCoreVersion } from "../use-core";
import { Button, Group, Row, Switch } from "./controls";
import { groupOf } from "./privacy";

/** Each extension's icon in a profile, as the engine draws them, by extension. */
function useExtensionIcons(session: Session, profileId: string, revision: unknown): ReadonlyMap<string, string> {
  const [icons, setIcons] = useState<ReadonlyMap<string, string>>(new Map());
  useEffect(() => {
    let current = true;
    const made: string[] = [];
    void session.core.request(ExtensionIcons({ profileId })).then((list) => {
      if (!current) return;
      const next = new Map<string, string>();
      for (const icon of list.icons) {
        if (!icon.image || icon.image.length === 0) continue;
        const url = URL.createObjectURL(new Blob([icon.image as BlobPart]));
        made.push(url);
        next.set(icon.extensionId, url);
      }
      setIcons(next);
    }, () => {});
    return () => {
      current = false;
      for (const url of made) URL.revokeObjectURL(url);
    };
  }, [session, profileId, revision]);
  return icons;
}

/**
 * The Mac's BrowserExtensionsView, a Space's Extensions: the extensions its
 * profile runs, each with its switch, what it may access, its settings and
 * removal, and copies in other Spaces; then where to add more.
 */
export function ExtensionsTab({ session, space, spaces }: { session: Session; space: SpaceState; spaces: readonly SpaceState[] }) {
  useCoreVersion(session);
  useSyncExternalStore((listener) => extensions.subscribe(listener), () => extensions.version);
  const revision = extensions.revision;
  const [refusal, setRefusal] = useState<string | null>(null);
  // The engine lists the profile's extensions again whenever they change.
  useEffect(() => {
    setRefusal(null);
    session.core.send(ListExtensions({ spaceId: space.id, engine: EngineKind.chromium })).catch((error: unknown) => {
      const kind = error instanceof CoreRejection ? error.rejection.$kind : null;
      setRefusal(kind === "SpaceIsPrivate" ? "Private windows don’t run extensions."
        : kind === "SpaceLocked" ? "Unlock this Space to see its extensions." : "Couldn’t list this Space’s extensions.");
    });
  }, [session, space.id, revision]);
  const listed = session.core.state.installedExtensions.get(space.profileId) ?? null;
  const icons = useExtensionIcons(session, space.profileId, listed);
  const installed = [...(listed ?? [])].sort((left, right) => left.name.localeCompare(right.name, undefined, { sensitivity: "base" }));
  const group = groupOf(space, spaces);
  const shared = group.members.length > 1;
  const [removing, setRemoving] = useState<InstalledExtension | null>(null);
  const [copying, setCopying] = useState<InstalledExtension | null>(null);
  const open = (address: string) => openExtensionPage(session, space, address);

  return (
    <>
      <Group title="Installed">
        {refusal ? (
          <Row title={<span className="settings-secondary-text">{refusal}</span>} />
        ) : listed === null ? (
          <div className="settings-row settings-progress-row"><span className="settings-progress" role="progressbar" aria-label="Loading" /></div>
        ) : installed.length === 0 ? (
          <Row title={<span className="settings-secondary-text">No extensions</span>} />
        ) : installed.map((item) => (
          <ExtensionRow key={item.id} item={item} icon={icons.get(item.id) ?? null}
            setEnabled={(on) => void change(session, space.id, item.id, on ? ExtensionChange.Enable : ExtensionChange.Disable)}
            options={() => item.optionsUrl && open(item.optionsUrl)}
            manage={() => open(extensionPages.details(item.id))}
            remove={() => setRemoving(item)}
            copy={() => setCopying(item)} />
        ))}
      </Group>
      <Group title="Add extensions">
        <div className="settings-row settings-buttons-row">
          <Button onClick={() => open(extensionPages.store())}>Open Chrome Web Store</Button>
          <Button onClick={() => open(extensionPages.manage())}>Chromium Extension Manager</Button>
          <span className="settings-spacer" />
          <Button onClick={() => open(extensionPages.shortcuts())}>Shortcuts…</Button>
        </div>
      </Group>
      {shared && <p className="settings-footer">Shared by {group.primary.settings.name}’s Sub-Spaces.</p>}
      <AnimatePresence>
        {removing && (
          <motion.div key="remove" className="sheet-backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <Sheet title="Remove Extension?" primary={`Remove from ${space.settings.name}`} secondary="Cancel" warning
              onPrimary={() => {
                void change(session, space.id, removing.id, ExtensionChange.Remove);
                setRemoving(null);
              }}
              onEscape={() => setRemoving(null)}>
              <p className="sheet-message">
                {shared ? `${removing.name} and its data are removed from every Space in this group.`
                  : `${removing.name} and its data are removed from this Space only.`}
              </p>
            </Sheet>
          </motion.div>
        )}
        {copying && (
          <motion.div key="copy" className="sheet-backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <CopySheet session={session} space={space} spaces={spaces} item={copying} onDone={() => setCopying(null)} />
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}

/** BrowserExtensionRow: the icon, name, version and summary, its switch, and the rest behind a disclosure. */
function ExtensionRow({ item, icon, setEnabled, options, manage, remove, copy }: {
  item: InstalledExtension;
  icon: string | null;
  setEnabled: (on: boolean) => void;
  options: () => void;
  manage: () => void;
  remove: () => void;
  copy: () => void;
}) {
  const [open, setOpen] = useState(false);
  return (
    <div className="settings-extension">
      <div className="settings-row">
        <button type="button" className="settings-disclosure" aria-expanded={open} aria-label={`${item.name} details`} onClick={() => setOpen(!open)}>
          <Symbol name={open ? "chevron.down" : "chevron.right"} size={10} />
        </button>
        <span className="settings-extension-icon">{icon ? <img src={icon} alt="" /> : <Symbol name="puzzlepiece.extension" size={16} />}</span>
        <div className="settings-row-text">
          <span className="settings-row-title">
            <span className="settings-truncates">{item.name}</span>
            <span className="settings-extension-version">{item.version}</span>
          </span>
          {item.description && <span className="settings-row-subtitle settings-clamps">{item.description}</span>}
          {item.fromWebStore && <span className="settings-row-subtitle settings-extension-source">From Chrome Web Store</span>}
        </div>
        <Switch label={`${item.name} enabled`} checked={item.enabled} disabled={!item.changeable} onChange={setEnabled} />
      </div>
      {open && (
        <div className="settings-extension-details">
          {item.fromWebStore && <button type="button" className="settings-link-button" onClick={copy}>Install a copy in other spaces</button>}
          {item.permissions.length > 0 && (
            <div className="settings-extension-permissions">
              <strong>Permissions and Website Access</strong>
              {item.permissions.map((permission) => <span key={permission}>{permission}</span>)}
            </div>
          )}
          <button type="button" className="settings-link-button" onClick={manage}>
            <Symbol name="hand.raised" size={12} /> Manage Permissions in Chromium
          </button>
          {item.optionsUrl && item.enabled && (
            <button type="button" className="settings-link-button" onClick={options}>
              <Symbol name="gearshape" size={12} /> Extension Settings
            </button>
          )}
          {item.changeable && (
            <button type="button" className="settings-link-button destructive" onClick={remove}>
              <Symbol name="trash" size={12} /> Remove Extension
            </button>
          )}
        </div>
      )}
    </div>
  );
}

/** BrowserExtensionCopySheet: the other Spaces a copy of a Web Store extension may go to, each chosen or not. */
function CopySheet({ session, space, spaces, item, onDone }: {
  session: Session;
  space: SpaceState;
  spaces: readonly SpaceState[];
  item: InstalledExtension;
  onDone: () => void;
}) {
  const [destinations, setDestinations] = useState<readonly string[] | null>(null);
  const [chosen, setChosen] = useState<readonly string[]>([]);
  useEffect(() => {
    void session.core.query(ExtensionCopyDestinations({ spaceId: space.id, engine: EngineKind.chromium, extensionId: item.id }))
      .then((answer) => setDestinations(answer.spaceIds), () => setDestinations([]));
  }, [session, space.id, item.id]);
  return (
    <Sheet title={`Install ${item.name} in Other Spaces`} primary="Install" secondary="Cancel"
      onPrimary={() => {
        onDone();
        const [first, ...rest] = chosen;
        if (first) void extensions.install(session, item.id, first, rest);
      }}
      onEscape={onDone}>
      <div className="extension-spaces" role="group" aria-label="Spaces">
        {destinations === null ? <p className="sheet-message">Finding Spaces…</p>
          : destinations.length === 0 ? <p className="sheet-message">Every Space that can run it has it already.</p>
            : destinations.map((spaceId) => {
              const checked = chosen.includes(spaceId);
              return (
                <label key={spaceId} className="extension-space">
                  <input type="checkbox" checked={checked}
                    onChange={() => setChosen(checked ? chosen.filter((id) => id !== spaceId) : [...chosen, spaceId])} />
                  {spaces.find((candidate) => candidate.id === spaceId)?.settings.name ?? "Space"}
                </label>
              );
            })}
      </div>
    </Sheet>
  );
}
