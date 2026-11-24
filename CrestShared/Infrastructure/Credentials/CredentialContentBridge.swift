import Foundation

/// The credential bridge every engine's pages run: its script and the name
/// its messages arrive under. How an engine installs it lives with the engine.
@MainActor
enum BrowserCredentialContentBridge {
    static let messageHandlerName = "crestCredentials"

    #if DEBUG
        private static let testingMethods = #"""
                ,
                inspectForTesting(selector) {
                  const selectedRoot = document.querySelector(selector);
                  const root = selectedRoot?.shadowRoot || selectedRoot;
                  if (!root) return null;
                  const reading = read(root);
                  return { formID: reading.formID, readingID: reading.readingID, fields: reading.fields };
                },
                captureForTesting(selector) {
                  const selectedRoot = document.querySelector(selector);
                  const root = selectedRoot?.shadowRoot || selectedRoot;
                  if (!root) return false;
                  capture(root, "submit", null);
                  return true;
                },
                focusForTesting(selector) {
                  const input = document.querySelector(selector);
                  if (!isReadable(input)) return false;
                  return reportFocus(input);
                }
            """#
    #else
        private static let testingMethods = ""
    #endif

    static let source = #"""
        (() => {
          "use strict";
          if (globalThis.__crestCredentialBridge) return;

          const handler = webkit.messageHandlers.crestCredentials;
          const maximumFields = 40;
          const maximumReadings = 32;
          const maximumText = 256;
          const maximumRules = 1024;
          const rootsByID = new Map();
          const idsByRoot = new WeakMap();
          const observersByRoot = new WeakMap();
          // Each recent reading's inputs, by the index the core names them
          // with, so a fill lands in the fields of the reading the core chose
          // them from, however the form changed since.
          const readings = new Map();
          let nextReadingID = 1;
          // The value the person last typed, pasted or dictated into each
          // input, or took from a password Crest made for them. A value the
          // page put there afterwards is not theirs.
          const enteredValues = new WeakMap();
          // Inputs that were password fields, still read as ones after a
          // "Show password" button turns them into text fields.
          const seenPasswords = new WeakSet();
          const seenPasswordReferences = new Set();
          let nextID = 1;
          let pendingSubmission = false;
          let fillingFocus = false;
          // The form whose focused field Crest's popup is open for. Its arrow,
          // Return and Escape keys go to the popup instead of the page.
          let heldForm = null;
          let trackedField = null;
          let trackedFieldRect = null;
          let lastSubmissionFingerprint = "";
          let lastSubmissionTime = 0;
          let observeRoot = () => {};

          const post = (body) => {
            try { handler.postMessage({ version: 2, ...body }); } catch (_) {}
          };

          const isVisible = (element) => {
            if (!isControl(element) || element.disabled) return false;
            const style = getComputedStyle(element);
            if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
            const rect = element.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0;
          };

          // Where the field sits in this frame's own viewport, in CSS pixels.
          // The host turns that into its own points; it is the only side that
          // knows the page's zoom, and the only side that knows whether this
          // frame is the one the prompt may be anchored inside.
          const rectOf = (element) => {
            const rect = element.getBoundingClientRect();
            if (!(rect.width > 0) || !(rect.height > 0)) return null;
            const values = [rect.left, rect.top, rect.width, rect.height];
            if (!values.every(Number.isFinite)) return null;
            return { x: rect.left, y: rect.top, width: rect.width, height: rect.height };
          };

          // The field's rect in the top page's viewport, adding the place of
          // each frame on the way up, as far as this frame can reach; the rect
          // in its own viewport, unmoved, from a frame it can't reach.
          const followedViews = new WeakSet();
          const placementOf = (element) => {
            const rect = rectOf(element);
            if (!rect) return null;
            let x = rect.x;
            let y = rect.y;
            let view = window;
            try {
              while (view !== view.top) {
                const frame = view.frameElement;
                if (!frame) return { rect, inTopViewport: false };
                const box = frame.getBoundingClientRect();
                x += box.left + frame.clientLeft;
                y += box.top + frame.clientTop;
                view = view.parent;
                // A page around the frame scrolling moves the field too.
                if (!followedViews.has(view)) {
                  followedViews.add(view);
                  view.addEventListener("scroll", () => reportFieldGeometry(), { capture: true, passive: true });
                }
              }
            } catch (_) {
              return { rect, inTopViewport: false };
            }
            return { rect: { x, y, width: rect.width, height: rect.height }, inTopViewport: true };
          };

          const rectsDiffer = (left, right) => !left || !right
            || Math.abs(left.x - right.x) >= 0.5
            || Math.abs(left.y - right.y) >= 0.5
            || Math.abs(left.width - right.width) >= 0.5
            || Math.abs(left.height - right.height) >= 0.5;

          // WebKit already delivers scroll events at most once per rendering
          // update, so the change gate below is the whole of the throttling:
          // a page that scrolls without moving the field posts nothing.
          // `frameMoved` is true when a page out of this frame's reach moved
          // it: the field stays put in the frame's own viewport, and the
          // engine adds the frame's new place to the rect.
          const reportFieldGeometry = (frameMoved) => {
            if (!trackedField) return;
            const input = trackedField.input.deref();
            if (!input || !input.isConnected || !isVisible(input)) {
              trackedField = null;
              trackedFieldRect = null;
              return;
            }
            const placement = placementOf(input);
            if (!placement) return;
            const movedOutOfReach = frameMoved === true && !placement.inTopViewport;
            if (!movedOutOfReach && !rectsDiffer(placement.rect, trackedFieldRect)) return;
            trackedFieldRect = placement.rect;
            post({
              event: "fieldGeometry",
              trusted: false,
              formID: trackedField.formID,
              fieldRect: placement.rect,
              topViewport: placement.inTopViewport
            });
          };

          const rootFor = (element) => {
            if (element.form) return element.form;
            const semanticRoot = element.closest("form, [role='form']");
            if (semanticRoot) return semanticRoot;
            const treeRoot = element.getRootNode();
            return treeRoot instanceof ShadowRoot ? treeRoot : document.body;
          };

          const pathOf = (event) => typeof event.composedPath === "function" ? event.composedPath() : [];

          const elementFromEvent = (event) =>
            pathOf(event).find((node) => node instanceof Element)
              || (event.target instanceof Element ? event.target : null);

          const isControl = (node) =>
            node instanceof HTMLInputElement || node instanceof HTMLSelectElement || node instanceof HTMLTextAreaElement;

          const inputFromEvent = (event) =>
            pathOf(event).find(isControl) || (isControl(event.target) ? event.target : null);

          const idFor = (root) => {
            let id = idsByRoot.get(root);
            if (!id) {
              id = `form-${nextID++}`;
              idsByRoot.set(root, id);
              rootsByID.set(id, new WeakRef(root));
              observeRoot(root);
            }
            return id;
          };

          const notePassword = (input) => {
            if (seenPasswords.has(input)) return;
            seenPasswords.add(input);
            seenPasswordReferences.add(new WeakRef(input));
          };

          const isPassword = (input) => input.type === "password" || seenPasswords.has(input);

          const autocompleteOf = (input) => (input.getAttribute("autocomplete") || "").trim().toLowerCase();

          // A control Crest can read and fill: a text, email, phone, number,
          // month or password field, a select or a text area for addresses
          // and cards, or a hidden field the page declares to hold the
          // username, as a change-password form does.
          const fillableTypes = ["text", "email", "tel", "number", "month"];
          const isReadable = (input) => {
            if (input instanceof HTMLSelectElement) return !input.disabled;
            if (input instanceof HTMLTextAreaElement) return !input.disabled && !input.readOnly;
            if (!(input instanceof HTMLInputElement) || input.disabled) return false;
            if (input.type === "hidden") return /(^|\s)(username|email)(\s|$)/.test(autocompleteOf(input));
            if (input.readOnly) return false;
            return fillableTypes.includes(input.type) || isPassword(input);
          };

          const typeOf = (input) =>
            input instanceof HTMLSelectElement ? "select" : input instanceof HTMLTextAreaElement ? "textarea" : input.type;

          const maximumOptions = 400;
          const optionsOf = (input) => input instanceof HTMLSelectElement
            ? Array.from(input.options).slice(0, maximumOptions)
              .map((option) => ({ value: textOf(option.value), text: textOf(option.text) }))
            : undefined;

          const isEntered = (input) => enteredValues.has(input) && enteredValues.get(input) === input.value;

          const textOf = (value, limit = maximumText) => (value || "").replace(/\s+/g, " ").trim().slice(0, limit);

          const labelOf = (input) => {
            const labels = input.labels ? Array.from(input.labels, (label) => label.textContent).join(" ") : "";
            const root = input.getRootNode();
            const named = (input.getAttribute("aria-labelledby") || "").split(/\s+/).filter(Boolean)
              .map((id) => root.getElementById?.(id)?.textContent || "").join(" ");
            return textOf(`${labels} ${input.getAttribute("aria-label") || ""} ${named}`);
          };

          const controlLabelOf = (control) => !control ? "" : textOf(
            control.innerText || control.value || control.getAttribute("aria-label") || control.title || ""
          );

          const describe = (input, index) => {
            const password = isPassword(input);
            if (password) notePassword(input);
            const field = {
              index,
              type: password ? "password" : typeOf(input),
              autocomplete: textOf(autocompleteOf(input)),
              name: textOf(input.name),
              id: textOf(input.id),
              label: labelOf(input),
              placeholder: textOf(input.placeholder),
              visible: isVisible(input),
              hasValue: password ? input.value.length > 0 : input.value.trim().length > 0,
              entered: isEntered(input),
              inputMode: textOf(input.getAttribute("inputmode"))
            };
            const options = optionsOf(input);
            if (options) field.options = options;
            if (input.minLength >= 0) field.minLength = input.minLength;
            if (input.maxLength >= 0) field.maxLength = input.maxLength;
            // Rules too long to read are left out whole, never cut short.
            const rules = password ? (input.getAttribute("passwordrules") || "").trim() : "";
            if (rules && rules.length <= maximumRules) field.passwordRules = rules;
            return field;
          };

          // The form's readable inputs, in the order the page shows them. A
          // scope that isn't a form leaves out the inputs of the forms inside it.
          // A form reads the controls it owns, its form attribute's too; any
          // other scope reads the inputs inside it.
          const read = (root) => {
            const controls = root instanceof HTMLFormElement ? root.elements : root.querySelectorAll("input, select, textarea");
            const inputs = Array.from(controls)
              .filter((input) => isReadable(input) && rootFor(input) === root)
              .slice(0, maximumFields);
            const formID = idFor(root);
            const readingID = nextReadingID++;
            readings.set(readingID, { formID, inputs: inputs.map((input) => new WeakRef(input)) });
            if (readings.size > maximumReadings) readings.delete(readings.keys().next().value);
            return { formID, readingID, inputs, fields: inputs.map(describe) };
          };

          // The values a reading holds, by index. `withPasswords` false leaves
          // every password out, as a focus must.
          const valuesOf = (reading, withPasswords) => {
            const values = {};
            reading.inputs.forEach((input, index) => {
              if (!withPasswords && isPassword(input)) return;
              const value = isPassword(input) ? input.value : input.value.trim();
              if (value) values[index] = value;
            });
            return values;
          };

          // A form being sent. The core decides whether it was, and what to
          // keep; this reports how it went and what the person entered.
          const capture = (root, trigger, control) => {
            const reading = read(root);
            const values = valuesOf(reading, true);
            const keys = Object.keys(values);
            if (!keys.length) return;
            const hasPassword = reading.inputs.some(isPassword);
            const now = Date.now();
            const fingerprint = [reading.formID, trigger, controlLabelOf(control),
              ...keys.map((key) => `${key}:${values[key].length}`)].join("\u0000");
            if (fingerprint === lastSubmissionFingerprint && now - lastSubmissionTime < 750) return;
            lastSubmissionFingerprint = fingerprint;
            lastSubmissionTime = now;
            if (hasPassword) pendingSubmission = true;
            post({
              event: hasPassword ? "submit" : "username",
              trusted: true,
              formID: reading.formID,
              readingID: reading.readingID,
              fields: reading.fields,
              values,
              submission: { trigger, inForm: root instanceof HTMLFormElement, label: controlLabelOf(control) }
            });
          };

          const hasVisiblePasswordField = () => {
            if (Array.from(document.querySelectorAll("input[type='password']")).some(isVisible)) {
              return true;
            }
            for (const reference of seenPasswordReferences) {
              const input = reference.deref();
              if (!input || !input.isConnected) {
                seenPasswordReferences.delete(reference);
                continue;
              }
              if (isVisible(input)) return true;
            }
            for (const [id, reference] of rootsByID) {
              const root = reference.deref();
              if (!root || !root.isConnected) {
                rootsByID.delete(id);
                continue;
              }
              if (root instanceof ShadowRoot
                  && Array.from(root.querySelectorAll("input[type='password']")).some(isVisible)) {
                return true;
              }
            }
            return false;
          };

          const reportDocumentState = () => post({
            event: "documentState",
            trusted: false,
            hasVisiblePasswordField: hasVisiblePasswordField()
          });

          const mutationOptions = {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ["hidden", "style", "class", "disabled", "type"]
          };

          const mutationDidOccur = () => {
            if (!pendingSubmission || hasVisiblePasswordField()) return;
            pendingSubmission = false;
            reportDocumentState();
          };

          observeRoot = (root) => {
            if (observersByRoot.has(root)) return;
            const observer = new MutationObserver(mutationDidOccur);
            observer.observe(root, mutationOptions);
            observersByRoot.set(root, observer);
          };

          // Asking the core what the focused field offers, and starting to
          // follow it. The listener and the testing hook go through here
          // together so the hook cannot drift away from the path a real focus
          // takes. A focus never carries a password.
          const reportFocus = (input) => {
            heldForm = null;
            const reading = read(rootFor(input));
            const index = reading.inputs.indexOf(input);
            if (index < 0) return false;
            const placement = placementOf(input);
            const rect = placement?.rect || null;
            trackedField = rect ? { input: new WeakRef(input), formID: reading.formID } : null;
            trackedFieldRect = rect;
            post({
              event: "focus",
              topViewport: placement?.inTopViewport || false,
              trusted: true,
              formID: reading.formID,
              readingID: reading.readingID,
              fields: reading.fields,
              focusedField: index,
              values: valuesOf(reading, false),
              fieldRect: rect || undefined
            });
            return true;
          };

          const setInputValue = (input, value) => {
            const prototype = input instanceof HTMLSelectElement ? HTMLSelectElement.prototype
              : input instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
            const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
            if (setter) setter.call(input, value); else input.value = value;
            input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertReplacementText", data: null }));
            input.dispatchEvent(new Event("change", { bubbles: true }));
          };

          const inputAt = (formID, readingID, index) => {
            const root = rootsByID.get(formID)?.deref();
            if (!root || !root.isConnected) {
              rootsByID.delete(formID);
              return null;
            }
            const reading = readings.get(readingID);
            if (!reading || reading.formID !== formID) return null;
            const input = reading.inputs[index]?.deref();
            return input && input.isConnected && !input.disabled && rootFor(input) === root ? input : null;
          };

          globalThis.__crestCredentialBridge = Object.freeze({
            // Writes each entry's value into the field the core named. A
            // password Crest made counts as the person's own; a saved one
            // doesn't, so sending it back unchanged asks nothing.
            fill(formID, readingID, entries, generated) {
              if (!Array.isArray(entries) || !entries.length) return false;
              const targets = entries.map((entry) => ({
                input: inputAt(formID, readingID, entry.index),
                value: String(entry.value)
              }));
              if (targets.some((target) => !target.input)) return false;
              for (const { input, value } of targets) {
                // A page that rebuilt the field while an earlier one filled
                // leaves this one detached: the fill failed.
                if (!input.isConnected || input.disabled) return false;
                setInputValue(input, value);
                if (generated) enteredValues.set(input, value); else enteredValues.delete(input);
              }
              heldForm = null;
              const last = targets[targets.length - 1].input;
              if (isVisible(last)) {
                fillingFocus = true;
                try { last.focus(); } finally { fillingFocus = false; }
              }
              return true;
            },
            // Moves focus to the form control before, -1, or after, 1, the
            // focused one, as the phone's previous and next buttons do.
            focusAdjacent(step) {
              const skipped = ["button", "submit", "reset", "image", "checkbox", "radio", "file", "range", "color", "hidden"];
              const controls = Array.from(document.querySelectorAll("input, select, textarea, [contenteditable='true']"))
                .filter((control) => !control.disabled && control.getClientRects().length
                  && !(control instanceof HTMLInputElement && skipped.includes(control.type)));
              const next = controls[controls.indexOf(document.activeElement) + step];
              if (!next) return false;
              next.focus();
              return true;
            },
            // Sends the focused field's arrow, Return and Escape keys to
            // Crest's popup while it is open for the form, or gives them back.
            holdKeys(formID, hold) {
              heldForm = hold ? formID : null;
              return true;
            },
            valueOf(formID, readingID, index) {
              const input = inputAt(formID, readingID, index);
              return input && !isPassword(input) ? input.value.trim() : null;
            }
            \#(testingMethods)
          });

          document.addEventListener("focusin", (event) => {
            const input = inputFromEvent(event);
            if (!event.isTrusted || fillingFocus || !isReadable(input) || input.type === "hidden") return;
            reportFocus(input);
          }, true);

          // The prompt is anchored under the focused field, so it stops
          // following once the page moves focus somewhere else. Focus leaving
          // the document altogether is the person reaching for the prompt
          // itself, which is exactly when it must keep following.
          document.addEventListener("focusout", (event) => {
            if (!trackedField || trackedField.input.deref() !== event.target) return;
            if (event.relatedTarget instanceof Element) {
              trackedField = null;
              trackedFieldRect = null;
              heldForm = null;
            }
          }, true);

          // Recorded before the page's own handlers run, and for a field that
          // isn't a password, again after them in case they reformat what was
          // typed. A password the page rewrites is no longer the person's.
          const noteEntered = (event) => {
            const input = inputFromEvent(event);
            if (!event.isTrusted || !input) return;
            enteredValues.set(input, input.value);
            // Typing in the field closes the popup and gives its keys back,
            // so Return sends what the person typed.
            if (heldForm && idsByRoot.get(rootFor(input)) === heldForm) {
              const formID = heldForm;
              heldForm = null;
              post({ event: "key", trusted: true, formID, key: "dismiss" });
            }
          };
          document.addEventListener("input", noteEntered, true);
          addEventListener("input", (event) => {
            const input = inputFromEvent(event);
            if (input && !isPassword(input)) noteEntered(event);
          });

          addEventListener("scroll", reportFieldGeometry, { capture: true, passive: true });
          addEventListener("resize", reportFieldGeometry, { passive: true });

          // A frame from another site can't see the pages around it scroll,
          // though its fields move with them. The frame holding the focus
          // hears of each move, once an animation frame, and passes it down.
          const frameMovedSignal = "crest-credential-frame-moved";
          let frameMoveQueued = false;
          const tellFocusedFrame = () => {
            if (frameMoveQueued) return;
            const frame = document.activeElement;
            if (!(frame instanceof HTMLIFrameElement || frame instanceof HTMLFrameElement)) return;
            frameMoveQueued = true;
            requestAnimationFrame(() => {
              frameMoveQueued = false;
              try { frame.contentWindow?.postMessage(frameMovedSignal, "*"); } catch (_) {}
            });
          };
          addEventListener("scroll", tellFocusedFrame, { capture: true, passive: true });
          addEventListener("message", (event) => {
            if (window === window.top || event.source !== window.parent || event.data !== frameMovedSignal) return;
            reportFieldGeometry(true);
            tellFocusedFrame();
          });

          document.addEventListener("submit", (event) => {
            if (!event.isTrusted || !(event.target instanceof HTMLFormElement)) return;
            capture(event.target, "submit", event.submitter);
          }, true);

          document.addEventListener("click", (event) => {
            if (!event.isTrusted) return;
            const target = elementFromEvent(event);
            if (!(target instanceof Element)) return;
            const control = target.closest(
              "button, input[type='submit'], input[type='image'], input[type='button'], [role='button']"
            );
            if (!control) return;
            const sendsForm = (control instanceof HTMLButtonElement && control.type === "submit")
              || (control instanceof HTMLInputElement && (control.type === "submit" || control.type === "image"));
            const root = rootFor(control);
            queueMicrotask(() => capture(root, sendsForm ? "submitControl" : "button", control));
          }, true);

          // Registered first, so a held key never reaches the page or the
          // Return capture below.
          const popupKeys = { ArrowDown: "down", ArrowUp: "up", Enter: "choose", Escape: "dismiss" };
          document.addEventListener("keydown", (event) => {
            const key = popupKeys[event.key];
            if (!heldForm || !key || !event.isTrusted || event.isComposing) return;
            const input = inputFromEvent(event);
            if (!input || idsByRoot.get(rootFor(input)) !== heldForm) return;
            event.preventDefault();
            event.stopImmediatePropagation();
            const formID = heldForm;
            if (key === "choose" || key === "dismiss") heldForm = null;
            post({ event: "key", trusted: true, formID, key });
          }, true);

          document.addEventListener("keydown", (event) => {
            const input = inputFromEvent(event);
            if (!event.isTrusted || event.isComposing || event.key !== "Enter" || !input) return;
            capture(rootFor(input), "return", null);
          }, true);

          const begin = () => {
            observeRoot(document.documentElement);
            reportDocumentState();
          };

          if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", begin, { once: true });
          } else {
            begin();
          }
        })();
        """#
}
