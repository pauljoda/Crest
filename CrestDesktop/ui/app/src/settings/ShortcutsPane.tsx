import {
  AssignShortcut,
  ChooseShortcutPreference,
  type KeyCombination,
  ReassignShortcut,
  ResetShortcut,
  ResetShortcuts,
  type ShortcutBinding,
  type ShortcutCommand,
  ShortcutModifiers,
  ShortcutPreference,
  ShortcutSection,
  UnassignShortcut,
} from "@crest/contracts";
import { CoreRejection } from "@crest/core-client";
import { AnimatePresence, motion } from "motion/react";
import { useEffect, useRef, useState } from "react";

import type { Session } from "../boot";
import { showContextMenu } from "../menus";
import { Sheet } from "../shell/prompts/PromptSheet";
import { commandTitle, keyCapture, pressedKeys, shortcutText } from "../shortcuts";
import { Symbol } from "../symbols";
import { useCoreVersion } from "../use-core";

/** A question the editor asks before it goes on. */
type Question =
  | { readonly kind: "conflict"; readonly command: ShortcutCommand; readonly keys: KeyCombination; readonly holders: readonly ShortcutCommand[] }
  | { readonly kind: "resetAll" };

/**
 * The Mac's BrowserShortcutSettingsView: a search field and Reset All… over
 * one list of every command by section, each with its keys in a recorder,
 * "Custom" where the person changed them, and a menu that clears them,
 * resets them, and chooses who takes them while a website uses them too.
 * Click a recorder, then press the new keys: Esc cancels, Backspace alone
 * clears. Keys another command holds ask before they move.
 */
export function ShortcutsPane({ session }: { session: Session }) {
  useCoreVersion(session);
  const shortcuts = session.core.state.shortcuts;
  const [search, setSearch] = useState("");
  const [recording, setRecording] = useState<string | null>(null);
  const [warning, setWarning] = useState<string | null>(null);
  const [question, setQuestion] = useState<Question | null>(null);
  const send = (intent: Parameters<typeof session.core.send>[0]) => session.core.send(intent);
  const bindings = shortcuts?.bindings ?? [];
  const query = search.trim().toLowerCase();
  const shown = bindings.filter((binding) => !query || commandTitle(binding.command).toLowerCase().includes(query)
    || (binding.command.searchTerms ?? "").toLowerCase().includes(query) || (binding.keys && shortcutText(binding.keys).toLowerCase().includes(query)));

  const assign = (command: ShortcutCommand, keys: KeyCombination) => {
    setRecording(null);
    send(AssignShortcut({ command, keys })).catch((error: unknown) => {
      if (!(error instanceof CoreRejection)) throw error;
      const rejection = error.rejection;
      if (rejection.$kind === "ShortcutInUse") setQuestion({ kind: "conflict", command, keys, holders: rejection.commands });
      else setWarning(`${shortcutText(keys)} is reserved by Crest.`);
    });
  };

  return (
    <div className="shortcuts-editor">
      <div className="shortcuts-controls">
        <span className="settings-search-field">
          <Symbol name="magnifyingglass" size={13} />
          <input value={search} placeholder="Search shortcuts" aria-label="Search shortcuts" onChange={(event) => setSearch(event.target.value)} />
        </span>
        <button type="button" className="settings-button" disabled={!shortcuts?.isCustomized} onClick={() => setQuestion({ kind: "resetAll" })}>
          Reset All…
        </button>
      </div>
      <AnimatePresence>
        {warning && (
          <motion.p key="warning" className="shortcuts-warning" role="alert" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <Symbol name="exclamationmark.triangle.fill" size={12} />
            {warning}
          </motion.p>
        )}
      </AnimatePresence>
      {shown.length === 0 && <p className="shortcuts-empty">No Results for “{search}”</p>}
      {ShortcutSection.all.map((section) => {
        const rows = shown.filter((binding) => binding.command.section === section);
        if (rows.length === 0) return null;
        return (
          <section key={section.name} className="settings-group">
            <div className="settings-group-header"><h3>{section.title}</h3></div>
            <div className="settings-card">
              {rows.map((binding) => (
                <ShortcutRow key={binding.command.name} session={session} binding={binding}
                  recording={recording === binding.command.name}
                  onRecord={(on) => {
                    setWarning(null);
                    setRecording(on ? binding.command.name : null);
                  }}
                  onKeys={(keys) => assign(binding.command, keys)}
                  onClear={() => void send(UnassignShortcut({ command: binding.command })).catch(() => {})}
                  onInvalid={() => setWarning("Use a function key, or a key with Ctrl, Alt, or Shift.")} />
              ))}
            </div>
          </section>
        );
      })}
      <p className="settings-footer">Click a shortcut, then press the new keys.</p>
      <AnimatePresence>
        {question && (
          <motion.div key="question" className="sheet-backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            {question.kind === "conflict" ? (
              <Sheet title="Shortcut Already in Use" primary="Replace Existing Shortcut" secondary="Cancel" warning
                onPrimary={() => {
                  void send(ReassignShortcut({ command: question.command, keys: question.keys })).catch(() => {});
                  setQuestion(null);
                }}
                onEscape={() => setQuestion(null)}>
                <p className="sheet-message">
                  {shortcutText(question.keys)} is assigned to {question.holders.map(commandTitle).join(", ")}. Replacing it will clear the shortcut from that command.
                </p>
              </Sheet>
            ) : (
              <Sheet title="Reset all Crest shortcuts?" primary="Reset Crest Shortcuts" secondary="Cancel" warning
                onPrimary={() => {
                  void send(ResetShortcuts()).catch(() => {});
                  setQuestion(null);
                }}
                onEscape={() => setQuestion(null)}>
                <p className="sheet-message">Every Crest command will return to its default shortcut.</p>
              </Sheet>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function ShortcutRow({ session, binding, recording, onRecord, onKeys, onClear, onInvalid }: {
  session: Session;
  binding: ShortcutBinding;
  recording: boolean;
  onRecord: (on: boolean) => void;
  onKeys: (keys: KeyCombination) => void;
  onClear: () => void;
  onInvalid: () => void;
}) {
  const command = binding.command;
  const recorder = useRef<HTMLButtonElement>(null);
  // While it records, the window binds no keys, so every key reaches it.
  useEffect(() => {
    if (!recording) return;
    recorder.current?.focus();
    return keyCapture.begin();
  }, [recording]);
  const menu = (at: { clientX: number; clientY: number }) => void showContextMenu(session.shell, at, [
    { title: "Clear Shortcut", enabled: binding.keys !== null, run: onClear },
    { title: "Reset to Default", enabled: binding.isCustomized, run: () => void session.core.send(ResetShortcut({ command })).catch(() => {}) },
    ...(binding.choosesPreference ? [
      "separator" as const,
      {
        title: "When a Website Uses These Keys",
        submenu: ShortcutPreference.all.map((preference) => ({
          title: preference.title,
          checked: binding.preference === preference,
          run: () => void session.core.send(ChooseShortcutPreference({ command, preference })).catch(() => {}),
        })),
      },
    ] : []),
  ]);
  return (
    <div className="settings-row shortcut-row" onContextMenu={(event) => {
      event.preventDefault();
      menu(event);
    }}>
      <span className="settings-row-title shortcut-title">{commandTitle(command)}</span>
      {binding.isCustomized && <span className="shortcut-custom">Custom</span>}
      <button ref={recorder} type="button" className={`shortcut-recorder${recording ? " recording" : ""}`}
        title="Click, then press the new shortcut" aria-label={`${commandTitle(command)} shortcut`}
        onClick={() => onRecord(!recording)}
        onBlur={() => recording && onRecord(false)}
        onKeyDown={(event) => {
          if (!recording) return;
          event.preventDefault();
          event.stopPropagation();
          const plain = !event.ctrlKey && !event.altKey && !event.shiftKey && !event.metaKey;
          if (plain && event.key === "Escape") return onRecord(false);
          if (plain && (event.key === "Backspace" || event.key === "Delete")) {
            onRecord(false);
            return onClear();
          }
          const keys = pressedKeys(event.nativeEvent);
          if (!keys) return;
          const function_ = keys.isSpecialKey && /^f\d+$/.test(keys.key);
          const held = keys.modifiers & (ShortcutModifiers.Command | ShortcutModifiers.Option | ShortcutModifiers.Shift | ShortcutModifiers.Control);
          if (!function_ && !held) return onInvalid();
          onKeys(keys);
        }}>
        {recording ? "Type Shortcut" : binding.keys ? shortcutText(binding.keys) : "—"}
      </button>
      <button type="button" className="shortcut-actions" aria-label="Shortcut Actions" title="Shortcut Actions"
        onClick={(event) => {
          const bounds = event.currentTarget.getBoundingClientRect();
          menu({ clientX: bounds.left, clientY: bounds.bottom });
        }}>
        <Symbol name="ellipsis" size={14} />
      </button>
    </div>
  );
}
