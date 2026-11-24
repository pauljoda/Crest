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
          let trackedField = null;
          let trackedFieldRect = null;
          let lastSubmissionFingerprint = "";
          let lastSubmissionTime = 0;
          let observeRoot = () => {};

          const post = (body) => {
            try { handler.postMessage({ version: 2, ...body }); } catch (_) {}
          };

          const isVisible = (element) => {
            if (!(element instanceof HTMLInputElement) || element.disabled) return false;
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

          const rectsDiffer = (left, right) => !left || !right
            || Math.abs(left.x - right.x) >= 0.5
            || Math.abs(left.y - right.y) >= 0.5
            || Math.abs(left.width - right.width) >= 0.5
            || Math.abs(left.height - right.height) >= 0.5;

          // WebKit already delivers scroll events at most once per rendering
          // update, so the change gate below is the whole of the throttling:
          // a page that scrolls without moving the field posts nothing.
          const reportFieldGeometry = () => {
            if (!trackedField) return;
            const input = trackedField.input.deref();
            if (!input || !input.isConnected || !isVisible(input)) {
              trackedField = null;
              trackedFieldRect = null;
              return;
            }
            const rect = rectOf(input);
            if (!rect || !rectsDiffer(rect, trackedFieldRect)) return;
            trackedFieldRect = rect;
            post({
              event: "fieldGeometry",
              trusted: false,
              formID: trackedField.formID,
              fieldRect: rect
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

          const inputFromEvent = (event) =>
            pathOf(event).find((node) => node instanceof HTMLInputElement)
              || (event.target instanceof HTMLInputElement ? event.target : null);

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

          // An input that can hold an account's name or a password: a text,
          // email, phone or password field, or a hidden field the page
          // declares to hold the username, as a change-password form does.
          const isReadable = (input) => {
            if (!(input instanceof HTMLInputElement) || input.disabled) return false;
            if (input.type === "hidden") return /(^|\s)(username|email)(\s|$)/.test(autocompleteOf(input));
            if (input.readOnly) return false;
            return input.type === "text" || input.type === "email" || input.type === "tel" || isPassword(input);
          };

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
              type: password ? "password" : input.type,
              autocomplete: textOf(autocompleteOf(input)),
              name: textOf(input.name),
              id: textOf(input.id),
              label: labelOf(input),
              placeholder: textOf(input.placeholder),
              visible: isVisible(input),
              hasValue: password ? input.value.length > 0 : input.value.trim().length > 0,
              entered: isEntered(input)
            };
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
            const controls = root instanceof HTMLFormElement ? root.elements : root.querySelectorAll("input");
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
            const reading = read(rootFor(input));
            const index = reading.inputs.indexOf(input);
            if (index < 0) return false;
            const rect = rectOf(input);
            trackedField = rect ? { input: new WeakRef(input), formID: reading.formID } : null;
            trackedFieldRect = rect;
            post({
              event: "focus",
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
            const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set;
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
              const last = targets[targets.length - 1].input;
              if (isVisible(last)) {
                fillingFocus = true;
                try { last.focus(); } finally { fillingFocus = false; }
              }
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
            }
          }, true);

          // Recorded before the page's own handlers run, and for a field that
          // isn't a password, again after them in case they reformat what was
          // typed. A password the page rewrites is no longer the person's.
          const noteEntered = (event) => {
            const input = inputFromEvent(event);
            if (event.isTrusted && input) enteredValues.set(input, input.value);
          };
          document.addEventListener("input", noteEntered, true);
          addEventListener("input", (event) => {
            const input = inputFromEvent(event);
            if (input && !isPassword(input)) noteEntered(event);
          });

          addEventListener("scroll", reportFieldGeometry, { capture: true, passive: true });
          addEventListener("resize", reportFieldGeometry, { passive: true });

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
