#ifndef BOAZ_NATIVE_HTTP_WARNING_H_
#define BOAZ_NATIVE_HTTP_WARNING_H_
#include <memory>
#include "base/functional/callback.h"
#include "components/security_interstitials/core/https_only_mode_metrics.h"
namespace content { class WebContents; }
namespace boaz {
enum class HttpWarningDecision { kGoBack, kContinue, kLearnMore };
class NativeHttpWarning {
 public:
  virtual ~NativeHttpWarning() = default;
};
std::unique_ptr<NativeHttpWarning> ShowNativeHttpWarning(
    content::WebContents*,
    security_interstitials::https_only_mode::InterstitialReason,
    base::OnceCallback<void(HttpWarningDecision)>);
}
#endif
