#ifndef BOAZ_ADBLOCK_REQUEST_CONTEXT_H_
#define BOAZ_ADBLOCK_REQUEST_CONTEXT_H_
#include <optional>
#include "content/public/browser/content_browser_client.h"
#include "url/origin.h"
namespace net { class IsolationInfo; }
namespace content { class RenderFrameHost; }
namespace boaz {
struct AdblockRequestContext {
  enum class Status { kUnavailable, kAuthoritative };
  using Purpose = content::ContentBrowserClient::URLLoaderFactoryType;
  Purpose purpose;
  Status status = Status::kUnavailable;
  std::optional<url::Origin> top_level_origin;
  std::optional<url::Origin> frame_origin;
  // Origin authority only. Path-specific exceptions require separate document provenance.
};
// UI thread only. Copies values; never retains frame/profile/browser pointers.
// Input isolation_info must be the browser's WillCreateURLLoaderFactory argument.
AdblockRequestContext ResolveAdblockRequestContext(
    content::RenderFrameHost*, AdblockRequestContext::Purpose,
    const net::IsolationInfo&);
}
#endif
