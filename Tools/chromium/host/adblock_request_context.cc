#include "adblock_request_context.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/render_frame_host.h"
#include "net/base/isolation_info.h"
#include "url/origin.h"
namespace boaz {
AdblockRequestContext ResolveAdblockRequestContext(
    content::RenderFrameHost* frame, AdblockRequestContext::Purpose purpose,
    const net::IsolationInfo& isolation_info) {
  CHECK_CURRENTLY_ON(content::BrowserThread::UI);
  AdblockRequestContext result{purpose};
  using Purpose = AdblockRequestContext::Purpose;
  switch (purpose) {
    case Purpose::kDocumentSubResource:
      break;
    // Navigation frames can still describe the previous document. Worker
    // ancestor frames do not identify the worker's actual document context;
    // shared/service workers can have multiple clients. Do not invent a site.
    case Purpose::kNavigation:
    case Purpose::kDownload:
    case Purpose::kWorkerMainResource:
    case Purpose::kWorkerSubResource:
    case Purpose::kServiceWorkerScript:
    case Purpose::kServiceWorkerSubResource:
    case Purpose::kPrefetch:
    case Purpose::kDevTools:
    case Purpose::kEarlyHints:
      return result;
  }
  if (!frame || isolation_info.IsEmpty() || isolation_info.nonce() ||
      isolation_info.request_type() != net::IsolationInfo::RequestType::kOther)
    return result;
  const auto& top = isolation_info.top_frame_origin();
  const auto& origin = isolation_info.frame_origin();
  if (!top || !origin || top->opaque() || origin->opaque() ||
      !top->GetURL().SchemeIsHTTPOrHTTPS() || !origin->GetURL().SchemeIsHTTPOrHTTPS())
    return result;
  // Document factories use RFH's browser-computed subresource IsolationInfo,
  // including pending navigation origins. Reading GetLastCommittedURL here
  // would incorrectly attach the previous document's path to a new factory.
  result.top_level_url = top->GetURL();
  result.frame_url = origin->GetURL();
  result.status = AdblockRequestContext::Status::kAuthoritative;
  return result;
}
}
