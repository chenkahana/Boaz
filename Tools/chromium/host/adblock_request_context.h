#ifndef BOAZ_ADBLOCK_REQUEST_CONTEXT_H_
#define BOAZ_ADBLOCK_REQUEST_CONTEXT_H_
#include <optional>
#include "content/public/browser/content_browser_client.h"
#include "url/origin.h"
#include "net/base/schemeful_site.h"
namespace net { class IsolationInfo; }
namespace content { class RenderFrameHost; }
namespace boaz {
struct AdblockRequestContext {
  enum class Status { kUnavailable, kAuthoritative };
  using Purpose = content::ContentBrowserClient::URLLoaderFactoryType;
  Purpose purpose;
  Status status = Status::kUnavailable;
  std::optional<net::SchemefulSite> top_level_site;
  std::optional<url::Origin> source_origin;
  // Site authority does not identify an exact top-level host or document path.
};
// UI thread only. Copies values; never retains frame/profile/browser pointers.
// Inputs must be the browser-owned WillCreateURLLoaderFactory arguments; worker
// request_initiator identifies the worker, never a renderer request header.
AdblockRequestContext ResolveAdblockRequestContext(
    content::RenderFrameHost*, AdblockRequestContext::Purpose,
    const net::IsolationInfo&, const url::Origin& request_initiator);
}
#endif
