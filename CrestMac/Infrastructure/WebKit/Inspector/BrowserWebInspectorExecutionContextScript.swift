import Foundation

/// Reads Inspector's engine-backed context models without disabling Runtime,
/// which Inspector itself owns. No code is injected into the inspected page.
enum BrowserWebInspectorExecutionContextScript {
    static let source = """
        if (!globalThis.WI?.Frame?.Event || !WI.networkManager) {
            throw new Error('WebKit execution-context observation is unavailable.');
        }
        const key = messageName + '_contexts';
        const state = globalThis[key] ??= {
            identities: new WeakMap(), announced: new Set(), subscription: null
        };
        if (state.added) {
            WI.Frame.removeEventListener(WI.Frame.Event.ExecutionContextAdded, state.added, state);
            WI.Frame.removeEventListener(WI.Frame.Event.ExecutionContextsCleared, state.cleared, state);
        }
        state.added = null;
        state.cleared = null;
        state.subscription = subscription;
        state.announced.clear();
        if (!subscription) return;

        const publish = (method, parameters) => {
            globalThis.webkit.messageHandlers[messageName].postMessage({
                method, parameters: {...parameters, subscription}
            });
        };
        const created = (context, frame) => {
            if (context.target !== WI.pageTarget || !Number.isInteger(context.id)) return;
            let identity = state.identities.get(context);
            if (!identity) {
                identity = crypto.randomUUID();
                state.identities.set(context, identity);
            }
            if (state.announced.has(identity)) return;
            state.announced.add(identity);
            publish('Crest.executionContextCreated', {context: {
                id: context.id, identity, type: context.type, name: context.name,
                frameId: frame.id, origin: frame.securityOrigin ?? ''
            }});
        };
        state.added = event => created(event.data.context, event.target);
        state.cleared = event => {
            for (const context of event.data.contexts) {
                const identity = state.identities.get(context);
                if (!identity || !state.announced.delete(identity)) continue;
                publish('Crest.executionContextDestroyed', {id: context.id, identity});
            }
        };
        WI.Frame.addEventListener(WI.Frame.Event.ExecutionContextAdded, state.added, state);
        WI.Frame.addEventListener(WI.Frame.Event.ExecutionContextsCleared, state.cleared, state);
        // Subscribe and snapshot in the same frontend turn. Contexts arriving
        // during Inspector startup are then observed exactly once, not lost.
        for (const frame of WI.networkManager.frames) {
            for (const context of frame.executionContextList.contexts) created(context, frame);
        }
        """
}
