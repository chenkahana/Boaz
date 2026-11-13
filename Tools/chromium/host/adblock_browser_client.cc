#include "adblock_browser_client.h"
#include <utility>
#include "adblock_profile_state.h"
#include "adblock_request_context.h"
#include "adblock_request_type.h"
#include "adblock_url_loader_factory.h"
#include "bootstrap.h"
#include "base/functional/bind.h"
#include "base/task/thread_pool.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/browser_thread.h"
#include "services/network/public/mojom/network_context.mojom.h"
#include "services/network/public/mojom/url_loader_factory.mojom.h"
namespace boaz {
void MaybeProxyBlockingFactory(content::BrowserContext* browser_context,
    content::RenderFrameHost* frame,
    content::ContentBrowserClient::URLLoaderFactoryType purpose,
    const url::Origin& initiator, const net::IsolationInfo& isolation,
    network::mojom::URLLoaderFactoryOverridePtr* factory_override) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!NativeHostEnabled() || !browser_context || !factory_override) return;
  auto profile = NativeBlockingState(Profile::FromBrowserContext(browser_context));
  if (!profile) return;
  auto context = ResolveAdblockRequestContext(frame, purpose, isolation, initiator);
  if (context.status != AdblockRequestContext::Status::kAuthoritative) return;
  mojo::PendingRemote<network::mojom::URLLoaderFactory> downstream;
  if (*factory_override) {
    downstream = std::move((*factory_override)->overriding_factory);
  } else {
    *factory_override = network::mojom::URLLoaderFactoryOverride::New();
    (*factory_override)->overridden_factory_receiver = downstream.InitWithNewPipeAndPassReceiver();
  }
  auto receiver = (*factory_override)->overriding_factory.InitWithNewPipeAndPassReceiver();
  auto decide = base::BindRepeating(
      [](std::shared_ptr<AdblockProfileState> state, const GURL& url,
         const std::string& method, network::mojom::RequestDestination destination,
         int resource_type, const AdblockRequestContext& context) {
        if (!url.SchemeIsHTTPOrHTTPS())
          return AdblockDecision{AdblockDecision::Action::kAllow};
        const auto kind = AdblockRequestType(resource_type, destination);
        if (!kind || !context.source_origin)
          return AdblockDecision{AdblockDecision::Action::kUnsupported};
        return state->Evaluate(url, context.source_origin->GetURL(), *kind,
                               method, context.top_level_site);
      }, std::move(profile));
  BindAdblockURLLoaderFactory(std::move(receiver), std::move(downstream),
      std::move(context), std::move(decide),
      base::ThreadPool::CreateSequencedTaskRunner(
          {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
           base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN}));
}
}
