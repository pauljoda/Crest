/// Runs only in the debugger's isolated, closed-shadow-capable content world.
/// Native node references stay in that world until Inspector binds their IDs;
/// only immutable snapshot data crosses the first evaluation result.
enum BrowserChromeDebuggerDOMSnapshotScript {
    static let source = #"""
        const started = performance.now();
        const strings = [], stringIDs = new Map();
        let stringUnits = 0;
        const registryKey = typeof nodeRegistryKey === 'string' ? nodeRegistryKey : snapshotKey;
        if (globalThis.__crestDebuggerNodeRegistry?.key !== registryKey) {
            globalThis.__crestDebuggerNodeRegistry = {key: registryKey, ids: new WeakMap(), nodes: new Map(), sequence: 0};
        }
        const registry = globalThis.__crestDebuggerNodeRegistry;
        for (const [id, reference] of registry.nodes) if (!reference.deref()) registry.nodes.delete(id);
        const weakNodeIDs = [];
        const weakIdentifier = node => {
            let id = registry.ids.get(node);
            if (id === undefined) {
                if (registry.nodes.size >= 50000) throw new Error('This document exceeds Crest’s DOM node identity limit.');
                id = ++registry.sequence;
                registry.ids.set(node, id); registry.nodes.set(id, new WeakRef(node));
            }
            return id;
        };
        const intern = value => {
            value = String(value ?? '');
            if (!stringIDs.has(value)) {
                stringUnits += value.length;
                if (stringUnits > 8000000) throw new Error('This document exceeds Crest’s DOM snapshot string limit.');
                stringIDs.set(value, strings.length); strings.push(value);
            }
            return stringIDs.get(value);
        };
        const rare = () => ({index: [], value: []});
        const put = (column, index, value) => { column.index.push(index); column.value.push(value); };
        const nodes = {
            parentIndex: [], nodeType: [], nodeName: [], nodeValue: [], attributes: [],
            shadowRootType: rare(), textValue: rare(), inputValue: rare(),
            inputChecked: {index: []}, optionSelected: {index: []}, currentSourceURL: rare()
        };
        const layout = {nodeIndex: [], styles: [], bounds: [], text: [], stackingContexts: {index: []}};
        const textBoxes = {layoutIndex: [], bounds: [], start: [], length: []};
        const references = [], childFrameOwners = [];
        const scrollX = window.scrollX, scrollY = window.scrollY;
        const rect = r => [r.x + scrollX, r.y + scrollY, r.width, r.height];
        const isStackingContext = (element, style) => {
            if (element === document.documentElement) return true;
            if (['fixed', 'sticky'].includes(style.position)) return true;
            if (style.zIndex !== 'auto') {
                if (style.position !== 'static') return true;
                const parentDisplay = element.parentElement ? getComputedStyle(element.parentElement).display : '';
                if (['flex', 'inline-flex', 'grid', 'inline-grid'].includes(parentDisplay)) return true;
            }
            if (Number(style.opacity) < 1 || style.mixBlendMode !== 'normal' || style.isolation === 'isolate') return true;
            if (['transform', 'scale', 'rotate', 'translate', 'filter', 'backdropFilter', 'perspective', 'clipPath', 'maskImage']
                .some(key => style[key] && style[key] !== 'none')) return true;
            if (/\b(layout|paint|strict|content)\b/.test(style.contain)) return true;
            return /\b(opacity|transform|scale|rotate|translate|filter|perspective|clip-path|mask|mix-blend-mode)\b/.test(style.willChange);
        };
        let textUnits = 0;
        const visit = (node, parent) => {
            if (references.length >= 20000 || textUnits > 100000 || performance.now() - started > 3000) {
                throw new Error('This document exceeds Crest’s DOM snapshot size or time limit.');
            }
            const index = references.length;
            references.push(node);
            // WebKit's Inspector deliberately does not bind ASCII-whitespace
            // text nodes. Preserve them with weak identities in this world.
            weakNodeIDs.push(node.nodeType === Node.TEXT_NODE && /^[\t\n\f\r ]*$/.test(node.nodeValue ?? '')
                ? weakIdentifier(node) : 0);
            nodes.parentIndex.push(parent);
            nodes.nodeType.push(node.nodeType);
            nodes.nodeName.push(intern(node.nodeName));
            nodes.nodeValue.push(intern(node.nodeValue));
            const attributes = [];
            if (node.nodeType === Node.ELEMENT_NODE) {
                for (const attribute of node.attributes) attributes.push(intern(attribute.name), intern(attribute.value));
            }
            nodes.attributes.push(attributes);
            if (node instanceof ShadowRoot) put(nodes.shadowRootType, index, intern(node.mode));
            if (node instanceof HTMLTextAreaElement) put(nodes.textValue, index, intern(node.value));
            if (node instanceof HTMLInputElement) {
                put(nodes.inputValue, index, intern(node.value));
                if (node.checked) nodes.inputChecked.index.push(index);
            }
            if (node instanceof HTMLOptionElement && node.selected) nodes.optionSelected.index.push(index);
            if ((node instanceof HTMLImageElement || node instanceof HTMLMediaElement) && node.currentSrc) {
                put(nodes.currentSourceURL, index, intern(node.currentSrc));
            }
            if (node instanceof HTMLIFrameElement || node instanceof HTMLFrameElement) childFrameOwners.push(index);
            let bounds, style, sourceText = '', range;
            if (node.nodeType === Node.ELEMENT_NODE && node.getClientRects().length) {
                bounds = rect(node.getBoundingClientRect());
                style = getComputedStyle(node);
            } else if (node.nodeType === Node.TEXT_NODE) {
                range = document.createRange(); range.selectNodeContents(node);
                const rectangles = Array.from(range.getClientRects()).filter(r => r.width > 0 && r.height > 0);
                if (rectangles.length) {
                    bounds = rect(range.getBoundingClientRect());
                    const parentElement = node.parentElement ?? node.getRootNode().host;
                    style = parentElement ? getComputedStyle(parentElement) : undefined;
                    sourceText = node.nodeValue ?? '';
                }
            }
            if (bounds) {
                const layoutIndex = layout.nodeIndex.length;
                layout.nodeIndex.push(index);
                layout.bounds.push(bounds);
                layout.styles.push(computedStyles.map(property => intern(style?.getPropertyValue(property) ?? '')));
                layout.text.push(intern(sourceText));
                if (node.nodeType === Node.ELEMENT_NODE && isStackingContext(node, style)) layout.stackingContexts.index.push(layoutIndex);
                // Ranges provide WebKit's actual rendered positions. Keep
                // UTF-16 offsets into source text, including surrogate pairs.
                if (range) {
                    let offset = 0;
                    for (const character of sourceText) {
                        textUnits += character.length;
                        if (textUnits > 100000 || (textUnits % 256 === 0 && performance.now() - started > 3000)) {
                            throw new Error('This document exceeds Crest’s DOM snapshot text limit.');
                        }
                        range.setStart(node, offset); range.setEnd(node, offset + character.length);
                        for (const r of range.getClientRects()) {
                            if (r.width <= 0 || r.height <= 0) continue;
                            textBoxes.layoutIndex.push(layoutIndex); textBoxes.bounds.push(rect(r));
                            textBoxes.start.push(offset); textBoxes.length.push(character.length);
                        }
                        offset += character.length;
                    }
                }
            }
            for (const child of node.childNodes) visit(child, index);
            if (node.nodeType === Node.ELEMENT_NODE && node.shadowRoot) visit(node.shadowRoot, index);
            if (node instanceof HTMLTemplateElement) visit(node.content, index);
        };
        visit(document, -1);
        const root = document.documentElement, scrolling = document.scrollingElement ?? root;
        const data = {
            documentURL: intern(document.URL), title: intern(document.title), baseURL: intern(document.baseURI),
            contentLanguage: intern(document.documentElement?.lang), encodingName: intern(document.characterSet),
            publicId: intern(document.doctype?.publicId), systemId: intern(document.doctype?.systemId),
            nodes, layout, textBoxes, scrollOffsetX: scrollX, scrollOffsetY: scrollY,
            contentWidth: Math.max(scrolling?.scrollWidth ?? 0, root?.clientWidth ?? 0),
            contentHeight: Math.max(scrolling?.scrollHeight ?? 0, root?.clientHeight ?? 0)
        };
        globalThis.__crestDebuggerSnapshots ??= new Map();
        globalThis.__crestDebuggerSnapshots.set(snapshotKey, references);
        return {document: data, strings, childFrameOwners, weakNodeIDs};
        """#
}
