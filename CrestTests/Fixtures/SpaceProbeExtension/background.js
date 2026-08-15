browser.runtime.onInstalled.addListener(async () => {
  const state = await browser.storage.local.get("installationCount");
  await browser.storage.local.set({
    installationCount: (state.installationCount ?? 0) + 1
  });
});

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.name !== "crest-sender-probe") return false;

  Promise.resolve().then(() => {
    if (!sender.tab?.id || typeof sender.frameId !== "number") {
      throw new Error("Missing tab or frame metadata");
    }
    return {
      tabID: sender.tab.id,
      frameID: sender.frameId,
      url: sender.url
    };
  }).then(
    data => sendResponse({ type: "Success", data }),
    error => sendResponse({ type: "Error", message: error.message })
  );
  return true;
});
