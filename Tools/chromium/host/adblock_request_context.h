#ifndef BOAZ_ADBLOCK_REQUEST_CONTEXT_H_
#define BOAZ_ADBLOCK_REQUEST_CONTEXT_H_
#include <optional>
#include "content/public/browser/content_browser_client.h"
#include "url/gurl.h"
namespace net { class IsolationInfo; }
namespace content { class RenderFrameHost; }
namespace boaz {
struct AdblockRequestContext {
  enum class Status { kUnavailable, kAuthoritative };
  using Purpose = content::ContentBrowserClient::URLLoaderFactoryType;
  Purpose purpose;
  Status status = Status::kUnavailable;
  std::optional<GURL> top_level_url;
  std::optional<GURL> frame_url;
  // These identify origins, never a document path. Path-specific exceptions
  // require additional document provenance and must not match these URLs.
  bool urls_are_origin_only = true;
};
// UI thread only. Copies values; never retains frame/profile/browser pointers.
// Input isolation_info must be the browser's WillCreateURLLoaderFactory argument.
AdblockRequestContext ResolveAdblockRequestContext(
    content::RenderFrameHost*, AdblockRequestContext::Purpose,
    const net::IsolationInfo&);
}
#endif
