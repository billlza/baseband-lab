import { localOrigin } from "./table.js";

chrome.action.onClicked.addListener(async (tab) => {
  const url = new URL(chrome.runtime.getURL("panel.html"));
  const origin = localOrigin(tab.url);
  if (origin && Number.isInteger(tab.id)) {
    url.searchParams.set("origin", origin);
    url.searchParams.set("tab", String(tab.id));
  }
  await chrome.windows.create({ url: url.href, type: "popup", width: 660, height: 720 });
});
