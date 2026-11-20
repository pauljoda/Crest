import { EngineKind, ExtensionCopyDestinations, type ExtensionInstallQuestion, type SpaceState } from "@crest/contracts";
import { AnimatePresence, motion } from "motion/react";
import { useEffect, useMemo, useState, useSyncExternalStore } from "react";

import type { Session } from "../../boot";
import { extensions } from "../../extensions";
import { Symbol } from "../../symbols";
import { useCoreVersion } from "../../use-core";
import { Sheet } from "./PromptSheet";

/** An image the engine handed over as bytes, as an address the page can show while it is shown. */
export function useImageBytes(bytes: Uint8Array | null | undefined): string | null {
  const url = useMemo(() => (bytes && bytes.length > 0 ? URL.createObjectURL(new Blob([bytes as BlobPart])) : null), [bytes]);
  useEffect(() => () => {
    if (url) URL.revokeObjectURL(url);
  }, [url]);
  return url;
}

/**
 * The Mac's BrowserChromeWebStoreInstallView, as a dialog over the window: the
 * extension's icon and name, the package downloading and being prepared,
 * then the core's question, what it may access, where it installs and in
 * which other Spaces, and Add Extension, which waits a moment so a click
 * meant for something else doesn't land on it; then that it is ready, or why
 * it failed.
 */
export function ExtensionReviewLayer({ session, spaces }: { session: Session; spaces: readonly SpaceState[] }) {
  useSyncExternalStore((listener) => extensions.subscribe(listener), () => extensions.version);
  useCoreVersion(session);
  const review = extensions.review;
  const removal = extensions.removal;
  const removalName = removal
    ? [...session.core.state.installedExtensions.values()].flat().find((item) => item.id === removal.extensionId)?.name ?? "This extension"
    : null;
  return (
    <div className="window-dialog-layer">
      <AnimatePresence>
        {review && (
          <motion.div key={review.installId} className="sheet-backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <InstallReview session={session} spaces={spaces} />
          </motion.div>
        )}
        {removal && !review && (
          <motion.div key="removal" className="sheet-backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <Sheet title="Remove Extension?" primary={`Remove from ${spaces.find((space) => space.id === removal.spaceId)?.settings.name ?? "Space"}`}
              secondary="Cancel" warning onPrimary={() => extensions.settleRemoval(session, true)} onEscape={() => extensions.settleRemoval(session, false)}>
              <p className="sheet-message">{removalName} and its data are removed from this Space.</p>
            </Sheet>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function InstallReview({ session, spaces }: { session: Session; spaces: readonly SpaceState[] }) {
  const review = extensions.review!;
  const state = session.core.state;
  const install = state.extensionInstalls.get(review.installId);
  const asked = [...state.extensionPrompts.values()].find((prompt) => prompt.installId === review.installId) ?? null;
  // The question leaves once the install ends; the review keeps its name and icon to say it is ready.
  const [kept, keep] = useState<ExtensionInstallQuestion | null>(null);
  useEffect(() => {
    if (asked) keep(asked.question);
  }, [asked]);
  const question = asked?.question ?? null;
  const shown = question ?? kept;
  const space = spaces.find((candidate) => candidate.id === review.spaceId);
  const spaceName = space?.settings.name ?? "Space";
  const stage = install?.stage;
  const preparing = !stage || stage.isPreparing;
  const installing = stage?.isInstalling ?? false;
  const completed = stage?.name === "installed";
  const failure = install?.failure ?? null;
  const [withhold, setWithhold] = useState<boolean | null>(null);
  const withholds = withhold ?? question?.withholdsSiteAccess ?? false;
  const [canAccept, setCanAccept] = useState(false);
  const [accessOpen, setAccessOpen] = useState(true);
  const [choosingSpaces, setChoosingSpaces] = useState(false);
  const [destinations, setDestinations] = useState<readonly string[]>([]);
  const icon = useImageBytes(shown?.icon);
  // Accepting waits a moment after the question appears.
  const promptId = asked?.promptId ?? null;
  useEffect(() => {
    setCanAccept(false);
    if (!promptId) return;
    const timer = setTimeout(() => setCanAccept(true), 500);
    return () => clearTimeout(timer);
  }, [promptId]);
  // The Spaces a copy may go to, as the core answers it.
  useEffect(() => {
    void session.core.query(ExtensionCopyDestinations({ spaceId: review.spaceId, engine: EngineKind.chromium, extensionId: review.extensionId }))
      .then((answer) => setDestinations(answer.spaceIds), () => setDestinations([]));
  }, [session, review.spaceId, review.extensionId]);
  // An install whose Space went out of reach closes its review.
  useEffect(() => {
    if (failure?.closesReview) extensions.dismiss(session);
  }, [failure, session]);
  const dismiss = () => {
    if (!installing) extensions.dismiss(session);
  };
  const accept = () => {
    if (!completed && promptId && canAccept && !installing && !failure) extensions.accept(session, promptId, withholds);
  };
  const title = completed ? "Extension Installed" : shown?.name ?? "Install Extension";
  const copies = review.copySpaceIds;

  if (choosingSpaces) {
    return (
      <Sheet title="Install in Other Spaces" primary="Done" onPrimary={() => setChoosingSpaces(false)} onEscape={() => setChoosingSpaces(false)}>
        <p className="sheet-message">{question?.name ?? "The extension"} installs in {spaceName} and each Space chosen here.</p>
        <div className="extension-spaces" role="group" aria-label="Other Spaces">
          {destinations.length === 0 && <p className="sheet-message">No other Space can take a copy.</p>}
          {destinations.map((spaceId) => {
            const destination = spaces.find((candidate) => candidate.id === spaceId);
            const checked = copies.includes(spaceId);
            return (
              <label key={spaceId} className="extension-space">
                <input type="checkbox" checked={checked}
                  onChange={() => extensions.chooseCopies(checked ? copies.filter((id) => id !== spaceId) : [...copies, spaceId])} />
                {destination?.settings.name ?? "Space"}
              </label>
            );
          })}
        </div>
      </Sheet>
    );
  }

  return (
    <motion.div className="sheet extension-review" role="dialog" aria-modal="true" aria-label={title}
      initial={{ opacity: 0, scale: 1.04 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.98 }}
      onKeyDown={(event) => {
        if (event.key === "Escape") {
          event.preventDefault();
          dismiss();
        }
      }}>
      <div className="sheet-body">
        <div className="extension-review-header">
          <span className="extension-icon large">{icon ? <img src={icon} alt="" /> : <Symbol name="puzzlepiece.extension" size={22} />}</span>
          <div>
            <h2 className="sheet-title">{title}</h2>
            {shown && !completed && (
              <span className="extension-verified"><Symbol name="checkmark.seal.fill" size={12} /> Verified Chrome Web Store package</span>
            )}
          </div>
        </div>
        {preparing && !failure ? (
          review.downloaded !== null && review.downloaded < 1 ? (
            <div className="extension-progress" role="progressbar" aria-valuenow={Math.round(review.downloaded * 100)} aria-valuemin={0} aria-valuemax={100}>
              <span>Downloading extension…</span>
              <span className="extension-progress-track"><span style={{ width: `${review.downloaded * 100}%` }} /></span>
            </div>
          ) : (
            <p className="sheet-message extension-preparing"><span className="extension-spinner" aria-hidden /> Preparing extension…</p>
          )
        ) : completed ? (
          <>
            <p className="extension-ready"><Symbol name="checkmark.circle.fill" size={14} /> {shown?.name ?? "The extension"} is ready in {spaceName}.</p>
            {(install?.installedCount ?? 0) > 1 && <p className="sheet-message">Installed in {install!.installedCount - 1} additional Spaces.</p>}
          </>
        ) : question ? (
          <fieldset className="extension-question" disabled={installing}>
            {question.summary && <p className="sheet-message">{question.summary}</p>}
            <dl className="extension-facts">
              <dt>Install In</dt><dd>{spaceName} Space</dd>
              <dt>Version</dt><dd>{question.version}</dd>
            </dl>
            <p className="extension-caution">Only install extensions you trust. Review the access below before installing.</p>
            <button type="button" className="extension-disclosure" aria-expanded={accessOpen} onClick={() => setAccessOpen(!accessOpen)}>
              <Symbol name={accessOpen ? "chevron.down" : "chevron.right"} size={10} />
              <Symbol name="hand.raised.fill" size={12} />
              Review Access and Compatibility
            </button>
            {accessOpen && (
              <div className="extension-access">
                <strong>Permissions and Website Access</strong>
                {question.permissions.length === 0
                  ? <span className="sheet-message">No additional browser permissions requested.</span>
                  : <ul>{question.permissions.map((permission) => <li key={permission}>{permission}</li>)}</ul>}
                {question.canWithholdSiteAccess && (
                  <label className="extension-withhold">
                    <input type="checkbox" checked={withholds} onChange={(event) => setWithhold(event.target.checked)} />
                    Withhold website access until I grant it
                  </label>
                )}
              </div>
            )}
            <div className="extension-other-spaces">
              <button type="button" className="sheet-button" onClick={() => setChoosingSpaces(true)}>Install in other Spaces…</button>
              {copies.length > 0 && <span className="extension-caution">Additional Spaces: {copies.length}</span>}
            </div>
          </fieldset>
        ) : null}
        {failure && (
          <>
            <p className="extension-failure"><Symbol name="exclamationmark.triangle.fill" size={13} /> {failure.message}</p>
            {(install?.installedCount ?? 0) > 0 && <p className="extension-caution">Installed in {install!.installedCount} Spaces before this error.</p>}
          </>
        )}
      </div>
      <div className="sheet-actions">
        {completed ? (
          <button type="button" className="sheet-button primary" data-autofocus onClick={() => extensions.dismiss(session)}>Done</button>
        ) : (
          <>
            {question && !failure && (
              <button type="button" className="sheet-button primary" disabled={!canAccept || installing} onClick={accept}>
                {installing ? "Adding…" : "Add Extension"}
              </button>
            )}
            <button type="button" className="sheet-button" disabled={installing} onClick={dismiss}>Cancel</button>
          </>
        )}
      </div>
    </motion.div>
  );
}
