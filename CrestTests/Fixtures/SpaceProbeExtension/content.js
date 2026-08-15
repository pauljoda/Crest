async function exposeSpaceLocalState() {
  const state = await browser.storage.local.get("visitCount");
  const visitCount = (state.visitCount ?? 0) + 1;
  await browser.storage.local.set({ visitCount });
  document.documentElement.dataset.crestExtensionID = browser.runtime.id;
  document.documentElement.dataset.crestVisitCount = String(visitCount);
}

exposeSpaceLocalState();

browser.runtime.sendMessage({ name: "crest-sender-probe" }).then(response => {
  document.documentElement.dataset.crestSenderResponse = JSON.stringify(response);
});
