#ifndef BOAZ_ADBLOCK_URL_LOADER_FACTORY_H_
#define BOAZ_ADBLOCK_URL_LOADER_FACTORY_H_
#include <string>
#include "adblock_request_context.h"
#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "services/network/public/mojom/url_loader_factory.mojom-forward.h"
#include "services/network/public/mojom/fetch_api.mojom-shared.h"
#include "url/gurl.h"
namespace base { class SequencedTaskRunner; }
namespace boaz {
enum class AdblockDecision { kAllow, kBlock };
using AdblockDecider = base::RepeatingCallback<AdblockDecision(
    const GURL&, const std::string&, network::mojom::RequestDestination,
    const AdblockRequestContext&)>;
// Callback runs only on runner, synchronously; capture immutable/thread-safe
// rule ownership, never UI/profile objects. No rewrite/redirect decision exists.
void BindAdblockURLLoaderFactory(
    mojo::PendingReceiver<network::mojom::URLLoaderFactory>,
    mojo::PendingRemote<network::mojom::URLLoaderFactory>,
    AdblockRequestContext, AdblockDecider,
    scoped_refptr<base::SequencedTaskRunner> runner);
}
#endif
