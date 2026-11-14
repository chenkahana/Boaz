#ifndef BOAZ_ADBLOCK_BROWSER_CLIENT_H_
#define BOAZ_ADBLOCK_BROWSER_CLIENT_H_
#include "content/public/browser/content_browser_client.h"
#include "services/network/public/mojom/network_context.mojom-forward.h"
namespace boaz {
void MaybeProxyBlockingFactory(content::BrowserContext*, content::RenderFrameHost*,
    content::ContentBrowserClient::URLLoaderFactoryType, const url::Origin&,
    const net::IsolationInfo&, network::mojom::URLLoaderFactoryOverridePtr*);
}
#endif
