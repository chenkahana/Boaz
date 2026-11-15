// State every check reads back: chrome.storage.local "log" holds each event in order.
async function log(event, detail = {}) {
  const { log: entries = [] } = await chrome.storage.local.get("log");
  entries.push({ event, ...detail, at: Date.now() });
  await chrome.storage.local.set({ log: entries });
}

chrome.runtime.onInstalled.addListener(async () => {
  await chrome.action.setBadgeText({ text: "42" });
  await chrome.action.setBadgeBackgroundColor({ color: "#1a73e8" });
  chrome.contextMenus.create({ id: "page", title: "Parity: page item", contexts: ["page"] });
  chrome.contextMenus.create({ id: "action", title: "Parity: action item", contexts: ["action"] });
  await log("installed");
});

chrome.contextMenus.onClicked.addListener((info) => log("menu", { id: info.menuItemId }));

chrome.commands.onCommand.addListener((command, tab) => {
  // sidePanel.open() needs the command's user gesture, so it runs before anything awaits.
  const opened = command === "open-panel"
    ? chrome.sidePanel.open({ windowId: tab.windowId }).then(() => "opened", (error) => String(error))
    : Promise.resolve(undefined);
  opened.then((panel) => log("command", { command, panel }));
});

// With site access withheld, ask for the site as Chrome extensions do, so the toolbar shows its request button.
// Without site access the tab's URL isn't visible, so ask on every load; Chromium keeps only requests for sites
// whose access is withheld.
chrome.tabs.onUpdated.addListener(async (tabId, change) => {
  if (change.status !== "complete") return;
  if (await chrome.permissions.contains({ origins: ["https://example.com/*"] })) return;
  await chrome.permissions.addHostAccessRequest?.({ tabId }).catch((error) => log("access-request", { error: String(error) }));
});

chrome.sidePanel.onClosed?.addListener((info) => log("panel-closed", { path: info.path }));

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  (async () => {
    switch (message.type) {
      case "open-popup":
        await chrome.action.openPopup();
        break;
      case "open-panel":
        await chrome.sidePanel.open({ windowId: message.windowId });
        break;
      case "panel-on-click":
        await chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: message.value });
        break;
      case "toggle-panel-on-click": {
        const { openPanelOnActionClick } = await chrome.sidePanel.getPanelBehavior();
        await chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: !openPanelOnActionClick });
        break;
      }
      case "popup-window":
        await chrome.windows.create({ url: "popup.html?window", type: "popup", width: 400, height: 300 });
        break;
      case "content":
        await log("content", { url: sender.tab?.url });
        break;
    }
    reply({ ok: true });
  })().catch((error) => reply({ ok: false, error: String(error) }));
  return true;
});

// For automation: the service worker exposes the same entry points.
self.parity = {
  openPopup: () => chrome.action.openPopup(),
  openPanel: async () => chrome.sidePanel.open({ windowId: (await chrome.windows.getLastFocused()).id }),
  panelOnClick: (value) => chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: value }),
  popupWindow: () => chrome.windows.create({ url: "popup.html?window", type: "popup", width: 400, height: 300 }),
  log: async () => (await chrome.storage.local.get("log")).log ?? [],
  requestHost: () => chrome.permissions.request({ origins: ["https://example.org/*"] }),
};
