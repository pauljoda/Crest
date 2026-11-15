import Foundation

/// The content bridge that hides what the content filter hides in a page's
/// documents beyond what the page's engine blocks, so blocked ads leave no
/// empty boxes. It runs in every document, in Crest's own world, on both
/// engines. It asks the core as the document starts, for the site's hiding
/// rules and procedural filters. Once the answer says the page blocks, it
/// surveys the elements already there and those that appear, for as long as
/// the document lives, and asks again about their classes and ids, for the
/// lists' generic rules, and the frames, images and objects they load. The
/// survey never runs inside the page's own work: what changes is queued and
/// looked at once the page is idle, a few milliseconds at a time, and on a
/// page that keeps bringing nothing to hide it looks less often. It applies
/// the answer: style rules, the procedural filters, re-run as the document
/// changes, and the collapse of elements whose loads the filter blocks. On
/// Chromium the style rules go into user style sheets, which the page's
/// scripts can neither read nor override; WebKit has no such sheet, so there
/// they go into a sheet this world adopts and keeps in place. Generic rules
/// applied as elements appear, rather than by the engine as a page first
/// renders, keep sites from mistaking the hiding for a reason to complain
/// about blocking.
@MainActor
enum BrowserCosmeticFilterContentBridge {
    static let messageHandlerName = "crestCosmetics"

    /// Applies an answer, `answer`, in the document that asked.
    static let applyBody = "globalThis.__crestCosmetics?.apply(answer); return true;"
    /// Starts the element picker in the top document with `options`: the
    /// colour its highlight takes and whether it starts from what the person
    /// last right-clicked. Answers whether it started.
    static let pickBody = "return globalThis.__crestCosmetics?.pick(options) ?? false;"
    /// Gives the running picker one of the bar's commands, `command`.
    static let pickerCommandBody = "globalThis.__crestCosmetics?.command(command); return true;"

    /// What `pickBody` passes the picker: Crest's accent, which outlines what
    /// the person points at as it tints the bar's Block button, and whether
    /// it starts from what they last right-clicked.
    static func pickerOptions(fromContextMenu: Bool) -> [String: Any] {
        let accent = CrestBrandTheme.accentLightComponents
        return [
            "accent": "rgb(\(accent.red) \(accent.green) \(accent.blue))",
            "fromContextMenu": fromContextMenu,
        ]
    }

    static let source = #"""
        (() => {
          "use strict";
          if (globalThis.__crestCosmetics) return;
          const handler = globalThis.webkit?.messageHandlers?.crestCosmetics;
          if (!handler || !/^https?:$/.test(location.protocol)) return;

          const maximumNames = 4000, maximumResources = 400, maximumSeen = 20000;
          // The survey looks at what appears a few milliseconds at a time, and
          // slows down on a page that keeps asking without anything to hide:
          // this many asks about names in a row, with nothing hidden for this
          // long. It looks sooner and gathers its asks for less time while the
          // page brings things to hide.
          const sliceBudget = 4, maximumFruitless = 64, fruitlessAfter = 60000;
          const prompt = { look: 100, gather: 60 }, slowed = { look: 1000, gather: 500 };
          // Elements that never carry anything the lists hide.
          const quiet = new Set(["SCRIPT", "STYLE", "LINK", "META", "NOSCRIPT", "TEMPLATE", "BR", "HEAD", "TITLE", "BASE"]);
          const kinds = { IFRAME: "frame", FRAME: "frame", IMG: "image", EMBED: "object", OBJECT: "object" };
          const loading = "iframe,frame,img,embed,object";
          const seenClasses = new Set(), seenIds = new Set(), seenResources = new Set(), collapsed = new Set();
          const pending = { classes: [], ids: [], resources: [] };
          const procedural = [];
          const isTop = globalThis.top === globalThis;
          let stopped = false, first = true, blocking = false, surveying = false;
          let sendTimer = 0, proceduralTimer = 0, sweepTimer = 0, sheet = null, observer = null, inserted = 0;
          // The first ask goes again if no answer comes, a couple of times at
          // most, so one lost answer never leaves the document unfiltered.
          let firstRetry = 0, firstAsks = 0;
          // What the survey still has to look at: the observer's batches of
          // records, the subtrees that appeared, the elements of the current
          // one, and the elements whose names or sources changed.
          let batches = [], batchHead = 0, recordHead = 0, nodeHead = 0, roots = [], listed = null, listedHead = 0;
          const changed = new Set();
          // Asks about names since something was last hidden, and when that was.
          let fruitless = 0, lastHidden = performance.now();
          // The survey's next turn: an idle callback, a frame or a timer.
          let turn = 0, turnKind = "", fallbackTurn = 0;
          const idle = globalThis.requestIdleCallback?.bind(globalThis) ?? null;
          // An element is read through the prototypes: a page's named form
          // controls shadow a form's own properties, so a form holding an
          // input named "id" or "getAttribute" would answer with the input.
          const attribute = Element.prototype.getAttribute;
          const tagOf = Object.getOwnPropertyDescriptor(Element.prototype, "tagName").get;
          const parentOf = Object.getOwnPropertyDescriptor(Node.prototype, "parentElement").get;
          const connected = Object.getOwnPropertyDescriptor(Node.prototype, "isConnected").get;
          // A subtree's elements are listed once and looked at a slice at a
          // time. A walk through the live tree would lose its place when the
          // page replaced part of it between two slices.
          const selectAll = Element.prototype.querySelectorAll;
          const styleRules = [];
          // Chromium's renderer gives this world alone a way to add user style
          // sheets; WebKit has none.
          const userSheet = globalThis.__crestUserSheet ?? null;
          let scratch = null;

          const post = (message) => { try { handler.postMessage(message); } catch (_) {} };
          const hide = (element) => { try { element.style.setProperty("display", "none", "important"); } catch (_) {} };

          function sourceOf(element) {
            const value = tagOf.call(element) === "OBJECT" ? element.data : (element.currentSrc || element.src);
            return typeof value === "string" && /^https?:/.test(value) ? value : null;
          }

          function note(element) {
            const tag = tagOf.call(element);
            if (quiet.has(tag)) return;
            if (seenClasses.size + seenIds.size < maximumSeen) {
              // The attribute's text, which costs less to read than the class list.
              const names = attribute.call(element, "class");
              if (names) {
                for (const name of names.split(/\s+/)) {
                  if (name && !seenClasses.has(name)) { seenClasses.add(name); pending.classes.push(name); }
                }
              }
              const id = attribute.call(element, "id");
              if (id && !seenIds.has(id)) { seenIds.add(id); pending.ids.push(id); }
            }
            const kind = kinds[tag];
            const url = kind ? sourceOf(element) : null;
            if (!url) return;
            if (collapsed.has(url)) { hide(element); sawHidden(); return; }
            if (!seenResources.has(kind + " " + url) && seenResources.size < maximumSeen) {
              seenResources.add(kind + " " + url);
              pending.resources.push({ kind, url });
            }
          }

          // An element the page made odd enough to throw is passed over.
          function look(element) {
            try { note(element); } catch (_) {}
          }

          function sawHidden() {
            fruitless = 0;
            lastHidden = performance.now();
          }

          function pace() {
            return fruitless >= maximumFruitless && performance.now() - lastHidden > fruitlessAfter ? slowed : prompt;
          }

          // The survey. The page's own work comes first: the observer only
          // queues what changed, and the elements are looked at once the page
          // is idle, a few milliseconds at a time, so a page that changes its
          // document never waits for the survey. Where the engine has no idle
          // callbacks, the survey runs just after the next frame: a frame
          // callback of a frame's document runs in the middle of the frame,
          // after the top document's, which may still be working on it. A page
          // that has slowed down is looked at a while later.
          function wake() {
            if (turn || !surveying) return;
            if (pace() === slowed) {
              turnKind = "timer";
              turn = setTimeout(() => { turn = 0; begin(); }, slowed.look);
            } else {
              begin();
            }
          }

          function begin() {
            if (!surveying) return;
            if (idle) {
              turnKind = "idle";
              turn = idle(survey, { timeout: prompt.look });
            } else if (document.visibilityState === "hidden") {
              turnKind = "timer";
              turn = setTimeout(survey, 200);
            } else {
              turnKind = "frame";
              turn = requestAnimationFrame(() => { turnKind = "timer"; turn = setTimeout(survey, 0); });
              // A window that is covered may get no frames for a while.
              fallbackTurn = setTimeout(survey, 1000);
            }
          }

          function cancelWake() {
            if (turnKind === "idle") cancelIdleCallback(turn);
            else if (turnKind === "frame") cancelAnimationFrame(turn);
            else clearTimeout(turn);
            clearTimeout(fallbackTurn);
            turn = 0;
            fallbackTurn = 0;
          }

          // Runs `task` when the page is idle, or at once where the engine
          // has no idle callbacks.
          function whenIdle(task, wait) {
            if (idle) idle(task, { timeout: wait }); else task();
          }

          function survey(deadline) {
            cancelWake();
            if (!surveying) return;
            const spare = deadline && !deadline.didTimeout ? deadline.timeRemaining() : sliceBudget;
            const end = performance.now() + Math.max(1, Math.min(sliceBudget, spare));
            const late = () => performance.now() >= end;
            let count = 0;
            slice: while (true) {
              if (listed) {
                if (listedHead < listed.length) {
                  // An element the page removed meanwhile is passed over; put
                  // back, it comes again as a record.
                  const element = listed[listedHead++];
                  try { if (connected.call(element)) look(element); } catch (_) {}
                  if (++count % 32 === 0 && late()) break;
                  continue;
                }
                listed = null;
                listedHead = 0;
              }
              if (roots.length) {
                try { listed = selectAll.call(roots.pop(), "*"); } catch (_) {}
              } else if (batchHead < batches.length) {
                const batch = batches[batchHead];
                if (!take(batch[recordHead], end)) break;
                nodeHead = 0;
                if (++recordHead >= batch.length) { batchHead++; recordHead = 0; }
              } else if (changed.size) {
                for (const element of changed) {
                  changed.delete(element);
                  try { if (element.isConnected) look(element); } catch (_) {}
                  if (++count % 32 === 0 && late()) break slice;
                }
              } else {
                break;
              }
              if (late()) break;
            }
            if (batchHead === batches.length) { batches = []; batchHead = 0; recordHead = 0; nodeHead = 0; }
            if (pending.classes.length || pending.ids.length || pending.resources.length) schedule();
            if (procedural.length) rerunProcedural();
            scheduleSweep(500);
            adopt();
            if (listed || roots.length || batchHead < batches.length || changed.size) wake();
          }

          // One of the observer's records: an element that appeared is looked
          // at, and its subtree walked; an element whose names or source
          // changed is looked at again. A record that adds many elements is
          // taken a slice at a time; answers whether it is done.
          function take(record, end) {
            try {
              if (record.type !== "childList") {
                const target = record.target;
                if (target.nodeType === 1) changed.add(target);
                return true;
              }
              const nodes = record.addedNodes;
              while (nodeHead < nodes.length) {
                const node = nodes[nodeHead++];
                try {
                  if (node.nodeType === 1 && node.isConnected && !quiet.has(tagOf.call(node))) {
                    look(node);
                    if (node.firstElementChild) roots.push(node);
                  }
                } catch (_) {}
                if (nodeHead % 32 === 0 && performance.now() >= end) return nodeHead >= nodes.length;
              }
            } catch (_) {}
            return true;
          }

          // The observer keeps each batch of records as it comes and reads
          // none of it: even looking at a node costs this world a wrapper of
          // its own for it, which the survey makes later. What can't wait is
          // done here: a collapsed slot that content fills shows again before
          // the page paints, and WebKit's sheet goes back if the page took it.
          function observed(records) {
            batches.push(records);
            if (sweptCount) {
              for (const record of records) if (record.type === "childList") restoreIfFilled(record);
            }
            if (sheet) adopt();
            wake();
          }

          // The survey starts once the first answer says the page blocks, from
          // the document as it stands; a page that blocks nothing never runs
          // it. It runs as long as the document does.
          function startSurvey() {
            if (surveying || stopped) return;
            surveying = true;
            const root = document.documentElement;
            if (root) { look(root); roots.push(root); }
            observer = new MutationObserver(observed);
            observer.observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ["class", "id", "src", "data"] });
            // A page that moves within itself starts afresh.
            const fresh = () => { sawHidden(); wake(); };
            addEventListener("popstate", fresh);
            try { globalThis.navigation?.addEventListener("currententrychange", fresh); } catch (_) {}
            wake();
          }

          function schedule() {
            if (!sendTimer && !stopped) {
              const gather = pace().gather;
              sendTimer = setTimeout(() => whenIdle(send, gather), gather);
            }
          }

          function send() {
            sendTimer = 0;
            if (stopped) return;
            if (!first && !pending.classes.length && !pending.ids.length && !pending.resources.length) return;
            const names = pending.classes.length + pending.ids.length;
            post({
              version: 1, first, url: location.href,
              classes: pending.classes.splice(0, maximumNames), ids: pending.ids.splice(0, maximumNames),
              resources: pending.resources.splice(0, maximumResources),
            });
            // Only an ask about names counts toward slowing down: the app
            // answers only an ask that hides something, and most images are
            // never blocked.
            if (!first && names) fruitless++;
            if (first) {
              clearTimeout(firstRetry);
              firstRetry = setTimeout(() => {
                if (!blocking && !stopped && ++firstAsks < 3) { first = true; send(); }
              }, 2000);
            }
            first = false;
            if (pending.classes.length || pending.ids.length || pending.resources.length) schedule();
          }

          // Style rules go into one sheet this world adopts, put back if the
          // page replaces the document's adopted sheets, turns the sheet off
          // or deletes its rules.
          function adopt() {
            try {
              if (!sheet) return;
              if (sheet.disabled) sheet.disabled = false;
              if (sheet.cssRules.length !== inserted) {
                sheet.replaceSync(styleRules.join("\n"));
                inserted = sheet.cssRules.length;
              }
              if (!document.adoptedStyleSheets.includes(sheet)) {
                document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
              }
            } catch (_) {}
          }

          function addStyle(text) {
            if (userSheet) {
              // Each rule is parsed alone and kept as the browser writes it
              // back, so a malformed one can't swallow the rules after it.
              try {
                scratch ??= new CSSStyleSheet();
                const rules = [];
                for (const rule of text.split("\n")) {
                  if (!rule) continue;
                  try {
                    scratch.insertRule(rule, 0);
                    rules.push(scratch.cssRules[0].cssText);
                    scratch.deleteRule(0);
                  } catch (_) {}
                }
                if (rules.length) userSheet.insert(rules.join("\n"));
              } catch (_) {}
              return;
            }
            try {
              sheet ??= new CSSStyleSheet();
              adopt();
              for (const rule of text.split("\n")) {
                if (!rule) continue;
                try {
                  sheet.insertRule(rule, sheet.cssRules.length);
                  styleRules.push(rule);
                  inserted = sheet.cssRules.length;
                } catch (_) {}
              }
              adopt();
            } catch (_) {}
          }

          // Procedural filters: each is a chain of operators over the
          // document's elements, as the filter lists' extended syntax names
          // them. An operator this bridge does not know matches nothing.
          const pseudoElements = { "matches-css-before": "::before", "matches-css-after": "::after" };

          function tester(argument) {
            const pattern = /^\/(.*)\/([imsu]*)$/.exec(argument);
            if (pattern) {
              const expression = new RegExp(pattern[1], pattern[2]);
              return (value) => expression.test(value);
            }
            return null;
          }

          function relative(elements, argument) {
            const selector = argument.trim();
            const found = new Set();
            for (const element of elements) {
              try {
                if (selector.startsWith(">")) {
                  for (const match of element.querySelectorAll(":scope " + selector)) found.add(match);
                } else if (selector.startsWith("+")) {
                  const next = element.nextElementSibling;
                  if (next?.matches(selector.slice(1).trim())) found.add(next);
                } else if (selector.startsWith("~")) {
                  const rest = selector.slice(1).trim();
                  for (let next = element.nextElementSibling; next; next = next.nextElementSibling) {
                    if (next.matches(rest)) found.add(next);
                  }
                } else if (/^\s/.test(argument)) {
                  for (const match of element.querySelectorAll(selector)) found.add(match);
                } else if (element.matches(selector)) {
                  found.add(element);
                }
              } catch (_) {}
            }
            return [...found];
          }

          function step(operator, elements) {
            const argument = String(operator.arg ?? "");
            const pool = () => elements ?? [...document.querySelectorAll("body *")];
            try {
              switch (operator.type) {
                case "css-selector":
                  return elements ? relative(elements, argument) : [...document.querySelectorAll(argument)];
                case "has-text": {
                  const test = tester(argument) ?? ((value) => value.includes(argument));
                  return pool().filter((element) => test(element.textContent || ""));
                }
                case "has":
                  return pool().filter((element) => {
                    try { return !!element.querySelector(":scope " + argument.trim()); } catch (_) { return false; }
                  });
                case "min-text-length": {
                  const length = Number(argument);
                  return pool().filter((element) => (element.textContent || "").length >= length);
                }
                case "upward": {
                  const count = Number(argument);
                  const found = new Set();
                  for (const element of pool()) {
                    let target = null;
                    if (Number.isInteger(count) && count > 0) {
                      target = element;
                      for (let index = 0; index < count && target; index++) target = target.parentElement;
                    } else {
                      target = element.parentElement?.closest(argument) ?? null;
                    }
                    if (target) found.add(target);
                  }
                  return [...found];
                }
                case "matches-css":
                case "matches-css-before":
                case "matches-css-after": {
                  const colon = argument.indexOf(":");
                  if (colon < 1) return [];
                  const name = argument.slice(0, colon).trim(), expected = argument.slice(colon + 1).trim();
                  const test = tester(expected) ?? ((value) => value === expected);
                  return pool().filter((element) =>
                    test(getComputedStyle(element, pseudoElements[operator.type] ?? null).getPropertyValue(name).trim()));
                }
                case "matches-attr": {
                  const parts = /^"?([^"=]+)"?(?:="?(.*?)"?)?$/.exec(argument);
                  if (!parts) return [];
                  const name = parts[1], expected = parts[2];
                  const test = expected === undefined ? () => true : tester(expected) ?? ((value) => value === expected);
                  return pool().filter((element) => element.hasAttribute(name) && test(element.getAttribute(name)));
                }
                case "matches-path": {
                  const test = tester(argument) ?? ((value) => value.includes(argument));
                  return test(location.pathname + location.search) ? pool() : [];
                }
                case "xpath": {
                  const found = new Set();
                  for (const context of elements ?? [document]) {
                    const result = document.evaluate(argument, context, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
                    for (let index = 0; index < result.snapshotLength; index++) {
                      const node = result.snapshotItem(index);
                      if (node.nodeType === 1) found.add(node);
                    }
                  }
                  return [...found];
                }
                default:
                  return [];
              }
            } catch (_) {
              return [];
            }
          }

          function act(filter, element) {
            const action = filter.action;
            if (!action) { hide(element); return; }
            if (action.type === "remove") {
              element.remove();
            } else if (action.type === "style") {
              for (const declaration of String(action.arg).split(";")) {
                const colon = declaration.indexOf(":");
                if (colon > 0) {
                  element.style.setProperty(declaration.slice(0, colon).trim(), declaration.slice(colon + 1).trim(), "important");
                }
              }
            } else if (action.type === "remove-attr") {
              element.removeAttribute(action.arg);
            } else if (action.type === "remove-class") {
              element.classList.remove(action.arg);
            }
          }

          function runProcedural() {
            let acted = false;
            for (const filter of procedural) {
              let elements = null;
              for (const operator of filter.selector ?? []) {
                elements = step(operator, elements);
                if (!elements.length) break;
              }
              for (const element of elements ?? []) { try { act(filter, element); acted = true; } catch (_) {} }
            }
            if (acted) sawHidden();
          }

          // The procedural filters run again a moment after the document
          // changes, once the page is idle.
          function rerunProcedural() {
            if (proceduralTimer || stopped) return;
            proceduralTimer = setTimeout(() => whenIdle(() => {
              proceduralTimer = 0;
              if (!stopped) runProcedural();
            }, 500), 150);
          }

          // An ad slot left with nothing to show collapses: an element named as
          // one, or holding nothing but an ad label, that shows no text, image,
          // video, frame or control. Content never qualifies, since it is not
          // empty.
          const slotWord = /^(ad|ads|adv|advert|adverts|advertisement|advertising|adslot|adunit|adbox|adwrap|adwrapper|adcontainer|dfp|gpt|billboard|leaderboard|mpu|skyscraper|sponsor|sponsored)$/i;
          const adLabel = /^(advertisement|advertisements|advertising|ad|ads|sponsored|sponsored content|story continues below advertisement|anzeige|publicité|publicidad|pubblicità)$/i;
          const shown = "img,video,iframe,canvas,svg,picture,object,embed,input,button,textarea,select";
          // An image still to load, which has no box yet.
          const lazy = "picture,img[loading=lazy],img:not([src]),img[data-src],img[data-srcset],img[data-lazy-src]";
          // What an ad brings into a slot, which the filter itself collapses;
          // anything else added to a collapsed slot shows it again.
          const carriers = new Set(["SCRIPT", "STYLE", "LINK", "META", "NOSCRIPT", "TEMPLATE", "IFRAME", "FRAME", "OBJECT", "EMBED"]);
          const maximumRestores = 3;
          // Each collapsed slot's own inline display, which showing it again
          // puts back, and how often each slot was shown again.
          const swept = new WeakMap(), restores = new WeakMap();
          let sweptCount = 0;

          function namedAsSlot(element) {
            const name = (attribute.call(element, "id") ?? "") + " " + (attribute.call(element, "class") ?? "");
            return name.split(/[\s_-]+/).some((word) => slotWord.test(word));
          }

          function paints(element) {
            const box = element.getBoundingClientRect();
            return box.width > 2 && box.height > 2 && getComputedStyle(element).backgroundImage !== "none";
          }

          // Whether the element shows nothing: no text but an ad label, no
          // image, video, frame or control with a box, no image still to
          // load, and no background image, such as a banner drawn in CSS.
          function showsNothing(element) {
            const text = (element.innerText || "").trim();
            if (text && !adLabel.test(text)) return false;
            if (element.querySelector(lazy)) return false;
            for (const inner of element.querySelectorAll(shown)) {
              if (inner.tagName === "IMG" && !inner.complete) return false;
              const box = inner.getBoundingClientRect();
              if (box.width > 2 && box.height > 2) return false;
            }
            if (paints(element)) return false;
            const inner = element.getElementsByTagName("*");
            for (let index = 0; index < inner.length && index < 200; index++) {
              if (paints(inner[index])) return false;
            }
            return true;
          }

          function collapseIfEmpty(element) {
            if (!element || swept.has(element) || element === document.body || element === document.documentElement) return;
            if ((restores.get(element) ?? 0) >= maximumRestores) return;
            const box = element.getBoundingClientRect();
            if (box.height < 40 || box.width < 100 || !showsNothing(element)) return;
            swept.set(element, [element.style.getPropertyValue("display"), element.style.getPropertyPriority("display")]);
            sweptCount++;
            hide(element);
          }

          // Shows a collapsed slot again once something it may show arrives
          // inside it; the next sweep looks at it afresh, a few times at most.
          function restoreIfFilled(record) {
            if (!sweptCount) return;
            const fills = [...record.addedNodes].some((node) => node.nodeType === 1
              ? !carriers.has(node.tagName)
              : node.nodeType === 3 && node.textContent.trim() && !adLabel.test(node.textContent.trim()));
            if (!fills) return;
            for (let node = record.target, level = 0; node && node !== document.body && level < 256; node = parentOf.call(node), level++) {
              const kept = swept.get(node);
              if (!kept) continue;
              swept.delete(node);
              sweptCount--;
              restores.set(node, (restores.get(node) ?? 0) + 1);
              try { node.style.setProperty("display", kept[0], kept[1]); } catch (_) {}
              scheduleSweep(500);
              return;
            }
          }

          function sweep() {
            sweepTimer = 0;
            if (stopped || !blocking || !document.body) return;
            for (const element of document.body.querySelectorAll("[id],[class]")) {
              try { if (namedAsSlot(element)) collapseIfEmpty(element); } catch (_) {}
            }
            const texts = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            while (texts.nextNode()) {
              try {
                if (!adLabel.test(texts.currentNode.textContent.trim())) continue;
                let holder = parentOf.call(texts.currentNode);
                for (let level = 0; holder && level < 3; level++, holder = parentOf.call(holder)) {
                  if (holder.getBoundingClientRect().height >= 40) { collapseIfEmpty(holder); break; }
                }
              } catch (_) {}
            }
          }

          // The sweep reads layout, so it runs a while after the change that
          // prompted it, when the page is idle, or just after the next frame
          // where the engine has no idle callbacks.
          function scheduleSweep(delay) {
            if (sweepTimer || stopped || !blocking) return;
            sweepTimer = setTimeout(() => {
              if (idle) idle(sweep, { timeout: 1000 });
              else if (document.visibilityState === "hidden") sweep();
              else requestAnimationFrame(() => setTimeout(sweep, 0));
            }, delay);
          }

          function collapseKnown() {
            for (const element of document.querySelectorAll(loading)) {
              const url = sourceOf(element);
              if (url && collapsed.has(url)) hide(element);
            }
          }

          function stop() {
            stopped = true;
            surveying = false;
            observer?.disconnect();
            observer = null;
            cancelWake();
            batches = []; batchHead = 0; recordHead = 0; nodeHead = 0; roots = []; listed = null; listedHead = 0;
            changed.clear();
            clearTimeout(sendTimer);
            clearTimeout(firstRetry);
            clearTimeout(proceduralTimer);
            clearTimeout(sweepTimer);
          }

          function apply(answer) {
            if (stopped || !answer) return;
            if (!answer.blocks) { stop(); return; }
            const firstAnswer = !blocking;
            blocking = true;
            let hides = false;
            if (answer.style) { addStyle(answer.style); hides = true; }
            for (const text of answer.procedural ?? []) {
              try { procedural.push(JSON.parse(text)); } catch (_) {}
            }
            if (answer.procedural?.length) { runProcedural(); hides = true; }
            if (answer.collapse?.length) {
              for (const url of answer.collapse) collapsed.add(url);
              collapseKnown();
              hides = true;
            }
            if (hides) { sawHidden(); scheduleSweep(200); }
            if (firstAnswer) {
              clearTimeout(firstRetry);
              scheduleSweep(600);
              if (document.readyState !== "complete") {
                addEventListener("load", () => setTimeout(() => scheduleSweep(0), 1500), { once: true });
              }
              startSurvey();
            }
          }

          // The element picker, in the top document alone: the person points
          // at what to hide and the app's bar widens or narrows the choice and
          // blocks it on this site from now on. The picker outlines what it
          // offers in a closed shadow root over the page and reports what it
          // holds; the bar is the app's own.
          // The longest selector the core keeps in a rule.
          const maximumSelector = 1024;
          let picker = null, contextTarget = null;
          if (isTop) {
            addEventListener("contextmenu", (event) => {
              contextTarget = event.target instanceof Element ? event.target : null;
            }, true);
          }

          function stableName(value) {
            return value.length <= 40 && !/\d{3,}/.test(value) && !/^(css|sc|jsx|emotion|svelte)-/.test(value);
          }

          // The element's id, or its tag and up to three classes, numbered
          // among its kind when a sibling shares them.
          function selectorPart(element) {
            if (element.id && stableName(element.id)) return "#" + CSS.escape(element.id);
            const classes = [...element.classList].filter(stableName).slice(0, 3)
              .map((value) => "." + CSS.escape(value)).join("");
            let part = element.localName + classes;
            const parent = element.parentElement;
            if (parent) {
              const alike = [...parent.children].filter((child) => {
                try { return child.matches(part); } catch (_) { return false; }
              });
              if (alike.length > 1) {
                const same = [...parent.children].filter((child) => child.localName === element.localName);
                part += ":nth-of-type(" + (same.indexOf(element) + 1) + ")";
              }
            }
            return part;
          }

          function matching(selector) {
            try { return [...document.querySelectorAll(selector)]; } catch (_) { return []; }
          }

          // The element's unique id, or its tag and place among its parent's
          // children.
          function anchoredPart(element) {
            if (element.id && stableName(element.id) && matching("#" + CSS.escape(element.id)).length === 1) {
              return "#" + CSS.escape(element.id);
            }
            const parent = element.parentElement;
            return element.localName + (parent ? ":nth-child(" + ([...parent.children].indexOf(element) + 1) + ")" : "");
          }

          // The shortest chain of `partOf` parts, up to `limit`, that matches
          // the element alone, or null.
          function chainFor(element, partOf, limit) {
            const parts = [];
            for (let node = element; node && node.nodeType === 1 && parts.length < limit; node = node.parentElement) {
              if (node === document.documentElement) break;
              parts.unshift(node === document.body ? "body" : partOf(node));
              const chain = parts.join(" > "), found = matching(chain);
              if (found.length === 1 && found[0] === element) return chain;
              if (node === document.body) break;
            }
            return null;
          }

          // A selector that matches the element alone and that a rule can
          // hold: its names where they are unique, otherwise its place in
          // the page. Nothing else is blocked, since the rule hides every
          // element its selector matches on the site.
          function selectorFor(element) {
            if (element === document.body || element === document.documentElement) return null;
            const chain = chainFor(element, selectorPart, 6) ?? chainFor(element, anchoredPart, 40);
            return chain && chain.length <= maximumSelector ? chain : null;
          }

          // The element under the pointer that the picker offers: the first,
          // from the innermost, big enough to be an item rather than a word,
          // short of the page itself unless it floats over the page, as a
          // pop-up does.
          function itemAt(x, y, host) {
            let element = document.elementFromPoint(x, y);
            if (!element || element === host) return null;
            const viewport = innerWidth * innerHeight;
            for (let node = element; node && node !== document.body && node !== document.documentElement;
                 node = node.parentElement) {
              const box = node.getBoundingClientRect();
              const style = getComputedStyle(node);
              const floats = style.position === "fixed" || style.position === "sticky";
              if (box.width * box.height > viewport * 0.85 && !floats) return element === node ? null : element;
              if (style.display !== "inline" && box.width >= 48 && box.height >= 28) return node;
            }
            return element === document.body || element === document.documentElement ? null : element;
          }

          function make(className) {
            const element = document.createElement("div");
            element.className = className;
            return element;
          }

          function pick(options) {
            if (!isTop || picker || !document.documentElement || !options) return false;
            const host = document.createElement("crest-element-picker");
            host.style.cssText = "all:initial;position:fixed;inset:0;z-index:2147483647;pointer-events:none;";
            const root = host.attachShadow({ mode: "closed" });
            try {
              const style = new CSSStyleSheet();
              style.replaceSync(":host{all:initial}" +
                ".mark{position:fixed;box-sizing:border-box;border:2px solid " + options.accent + ";border-radius:6px;" +
                "background:color-mix(in srgb," + options.accent + " 12%,transparent);pointer-events:none;" +
                "transition:left .12s,top .12s,width .12s,height .12s}" +
                "@media (prefers-reduced-motion:reduce){.mark{transition:none}}");
              root.adoptedStyleSheets = [style];
            } catch (_) {}
            const marks = make("marks");
            root.append(marks);

            let chain = [], selector = null, hovered = null, frame = 0;
            const chosen = () => chain[chain.length - 1] ?? null;
            const inside = (event) => event.composedPath().includes(host);

            function draw() {
              frame = 0;
              const targets = chosen() ? matching(selector).slice(0, 60) : hovered ? [hovered] : [];
              while (marks.childElementCount > targets.length) marks.lastElementChild.remove();
              while (marks.childElementCount < targets.length) marks.append(make("mark"));
              targets.forEach((target, index) => {
                const box = target.getBoundingClientRect(), mark = marks.children[index];
                mark.style.left = box.left - 2 + "px";
                mark.style.top = box.top - 2 + "px";
                mark.style.width = box.width + 4 + "px";
                mark.style.height = box.height + 4 + "px";
              });
            }
            const redraw = () => { if (!frame) frame = requestAnimationFrame(draw); };

            // The bar the app shows follows what the picker holds.
            function report() {
              const parent = chosen()?.parentElement;
              post({ url: location.href, picker: {
                active: true, selector,
                canWiden: !!parent && parent !== document.body && parent !== document.documentElement,
                canNarrow: chain.length > 1,
              } });
            }

            function update() {
              const element = chosen();
              selector = element ? selectorFor(element) : null;
              redraw();
              report();
            }

            function choose(element) {
              chain = element ? [element] : [];
              hovered = null;
              update();
            }

            // Only the person's own input picks or blocks: an event the page
            // makes up passes through as if the picker were not there.
            function swallow(event) {
              if (!event.isTrusted || inside(event)) return;
              event.preventDefault();
              event.stopImmediatePropagation();
            }

            const listeners = {
              pointermove: (event) => {
                if (!event.isTrusted || chosen() || event.pointerType !== "mouse") return;
                const element = itemAt(event.clientX, event.clientY, host);
                if (element !== hovered) { hovered = element; redraw(); }
              },
              pointerdown: swallow, pointerup: swallow, mousedown: swallow, mouseup: swallow,
              auxclick: swallow, dblclick: swallow, contextmenu: swallow,
              click: (event) => {
                if (!event.isTrusted || inside(event)) return;
                swallow(event);
                choose(itemAt(event.clientX, event.clientY, host));
              },
              keydown: (event) => {
                if (!event.isTrusted) return;
                if (event.key === "Escape") { swallow(event); close(); }
                else if (event.key === "Enter" && selector) { swallow(event); commit(); }
              },
              scroll: redraw, resize: redraw,
            };

            function close() {
              if (picker === null) return;
              globalThis.navigation?.removeEventListener("currententrychange", close);
              for (const [name, listener] of Object.entries(listeners)) removeEventListener(name, listener, true);
              cancelAnimationFrame(frame);
              host.remove();
              picker = null;
              post({ url: location.href, picker: { active: false } });
            }

            // What the person blocked dissolves, then stays hidden by the
            // rule the app keeps.
            function commit() {
              if (!selector) return;
              const rule = selector, targets = matching(rule);
              post({ url: location.href, block: rule });
              close();
              const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
              for (const element of targets) {
                try {
                  element.animate(still
                    ? [{ opacity: 1 }, { opacity: 0 }]
                    : [{ opacity: 1, filter: "blur(0)", transform: "scale(1)" },
                       { opacity: 0, filter: "blur(10px)", transform: "scale(0.97)" }],
                    { duration: still ? 150 : 320, easing: "ease-out" }).finished.then(() => hide(element), () => hide(element));
                } catch (_) { hide(element); }
              }
              addStyle(rule + " { display: none !important; }");
            }

            const commands = {
              wider() { const parent = chosen()?.parentElement; if (parent) { chain.push(parent); update(); } },
              narrower() { if (chain.length > 1) { chain.pop(); update(); } },
              block: commit,
              cancel: close,
            };

            // The page leaving, into the back-forward cache or to another
            // entry of its history, ends the pick: what it outlined is gone.
            const ends = { pagehide: close, popstate: close, hashchange: close };
            Object.assign(listeners, ends);
            globalThis.navigation?.addEventListener("currententrychange", close);
            for (const [name, listener] of Object.entries(listeners)) addEventListener(name, listener, true);
            document.documentElement.append(host);
            picker = { command: (name) => commands[name]?.() };
            const target = options.fromContextMenu && contextTarget?.isConnected ? contextTarget : null;
            choose(target && target !== document.body && target !== document.documentElement ? target : null);
            return true;
          }

          function command(name) { picker?.command(name); }

          globalThis.__crestCosmetics = Object.freeze({ apply, pick, command });

          // The first ask names only the document, so the site's filters can
          // apply before it renders; the survey of what it shows starts with
          // the answer, if the page blocks anything.
          send();
        })();
        """#
}
