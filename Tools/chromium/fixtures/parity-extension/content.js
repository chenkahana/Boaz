document.documentElement.dataset.boazParity = "content-script";
chrome.runtime.sendMessage({ type: "content" });
