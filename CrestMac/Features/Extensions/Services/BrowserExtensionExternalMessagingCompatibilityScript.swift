/// Included inside the compatibility runtime's lexical scope, beside the
/// identity fragment. It reuses the runtime's own `capabilityWatch` and
/// `requestCapability`, and it is read by `normalizeRuntimeMessageEvent`
/// above, which registers each `runtime.onMessageExternal` listener here
/// together with the wrapper that listener already runs behind.
///
/// This is the extension half of one relay. A website named in an extension's
/// `externally_connectable` calls `chrome.runtime.sendMessage(extensionID, …)`,
/// and WebKit answers that itself — but only while the sending page resolves to
/// a browser tab. A frame inside a Crest-hosted extension document, such as the
/// vendor web app a side panel frames, never does:
/// `WebExtensionContext::runtimeWebPageSendMessage` looks the sender up as a
/// tab and drops the message when the lookup fails. Chrome has no such rule —
/// its side panel is not a tab either, which is exactly why `sender.tab` is
/// undefined for these deliveries — so Crest carries them, and this fragment is
/// where one arrives.
///
/// Nothing here decides whether the page was allowed to send. That gate belongs
/// to the Swift relay, which owns the sending frame's URL and checks it against
/// the extension's own `externally_connectable.matches` and host access. By the
/// time a delivery reaches this code it has already passed.
enum BrowserExtensionExternalMessagingCompatibilityScript {
    static let source = #"""
        // Runs one relayed web-page message through every registered
        // `onMessageExternal` listener and hands back the first Promise a
        // listener produced. That is what the runtime's listener wrapper
        // returns for `return true` plus `sendResponse`, for a returned
        // Promise, and for a synchronous `sendResponse`, so a relayed delivery
        // claims a response by exactly the rules a native one does.
        // `undefined` means nobody claimed it, which is Chrome's "the
        // receiving end does not exist".
        const dispatchRelayedExternalMessage = (message, sender) => {
            let claimed;
            for (const wrapper of Array.from(
                externalMessageListeners.values()
            )) {
                let result;
                try {
                    result = wrapper(message, sender);
                } catch {
                    continue;
                }
                if (claimed === undefined && result?.then instanceof Function) {
                    claimed = result;
                }
            }
            return claimed;
        };
        // The one-shot answer that completes the page's promise. An omitted
        // `response` is Chrome's unanswered message; `null` would be a value
        // the listener chose to send.
        const answerRelayedExternalMessage = (requestId, response) => {
            const payload = { requestId };
            if (response !== undefined) payload.response = response;
            try {
                const answered = requestCapability(
                    "runtime.externalMessageReply",
                    payload,
                    []
                );
                answered?.catch?.(() => {});
            } catch {}
        };
        const publishExternalMessage = (message) => {
            if (
                message?.api !== "runtime.externalMessage"
                || typeof message.requestId !== "string"
            ) {
                return;
            }
            const requestId = message.requestId;
            // Chrome's sender for a web page that is not a tab: where the
            // frame is and nothing else. No `tab`, because a side panel is not
            // one, and no `id`, because the sender is a website rather than an
            // extension.
            const nativeSender = message.sender ?? {};
            const sender = Object.freeze({
                url: typeof nativeSender.url === "string"
                    ? nativeSender.url
                    : undefined,
                origin: typeof nativeSender.origin === "string"
                    ? nativeSender.origin
                    : undefined,
                frameId: Number.isInteger(nativeSender.frameId)
                    ? nativeSender.frameId
                    : 0
            });
            const claimed = dispatchRelayedExternalMessage(
                message.message,
                sender
            );
            if (claimed === undefined) {
                answerRelayedExternalMessage(requestId, undefined);
                return;
            }
            claimed.then(
                (response) => answerRelayedExternalMessage(
                    requestId,
                    response
                ),
                () => answerRelayedExternalMessage(requestId, undefined)
            );
        };
        // Connected by the first `onMessageExternal` listener and dropped when
        // the last one goes. `runtime` gates on no permission in Chrome and
        // asks for none here: every extension may hear from a website it named
        // itself.
        externalMessageWatch = capabilityWatch({
            api: "runtime",
            hasListeners: () => externalMessageListeners.size > 0,
            onMessage: publishExternalMessage,
            subscription: () => ({ api: "runtime.watch" })
        });
        """#
}
