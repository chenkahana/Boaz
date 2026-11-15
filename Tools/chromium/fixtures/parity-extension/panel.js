chrome.storage.local.get("log").then(({ log = [] }) =>
  chrome.storage.local.set({ log: [...log, { event: "panel", at: Date.now() }] }));
