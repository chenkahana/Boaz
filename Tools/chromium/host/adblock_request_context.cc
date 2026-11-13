#include "adblock_request_context.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/render_frame_host.h"
#include "net/base/isolation_info.h"
#include "url/origin.h"
namespace boaz {
AdblockRequestContext ResolveAdblockRequestContext(
    content::RenderFrameHost* frame, AdblockRequestContext::Purpose purpose,
    const net::IsolationInfo& isolation_info, const url::Origin& request_initiator) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  AdblockRequestContext result{purpose};
  using Purpose = AdblockRequestContext::Purpose;
  bool worker = false;
  switch (purpose) {
    case Purpose::kDocumentSubResource:
      if (!frame) return result;
      break;
    case Purpose::kWorkerSubResource:
    case Purpose::kServiceWorkerScript:
    case Purpose::kServiceWorkerSubResource:
      worker = true;
      break;
    // Worker main-script and browser-initiated SW script factories currently
    // pass empty isolation. Navigation needs request-specific trusted context.
    case Purpose::kNavigation:
    case Purpose::kDownload:
    case Purpose::kWorkerMainResource:
    case Purpose::kPrefetch:
    case Purpose::kDevTools:
    case Purpose::kEarlyHints:
      return result;
  }
  if (isolation_info.IsEmpty() || isolation_info.nonce() ||
      isolation_info.network_isolation_key().IsTransient() ||
      isolation_info.request_type() != net::IsolationInfo::RequestType::kOther)
    return result;
  const auto& top = isolation_info.top_frame_origin();
  const auto& origin = isolation_info.frame_origin();
  if (!top || !origin || top->opaque() || origin->opaque() ||
      !top->GetURL().SchemeIsHTTPOrHTTPS() || !origin->GetURL().SchemeIsHTTPOrHTTPS())
    return result;
  const auto& source = worker ? request_initiator : *origin;
  if (source.opaque() || !source.GetURL().SchemeIsHTTPOrHTTPS()) return result;
  // Worker callers supply the actual worker origin separately. Shared/SW
  // isolation may reconstruct top origin from StorageKey's schemeful site;
  // converting to SchemefulSite preserves only the authority actually present.
  // Document factories use RFH's browser-computed subresource IsolationInfo,
  // including pending navigation origins. Reading GetLastCommittedURL here
  // would incorrectly attach the previous document's path to a new factory.
  result.top_level_site = net::SchemefulSite(*top);
  result.source_origin = source;
  result.status = AdblockRequestContext::Status::kAuthoritative;
  return result;
}
}
