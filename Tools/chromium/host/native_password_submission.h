#ifndef BOAZ_CHROMIUM_NATIVE_PASSWORD_SUBMISSION_H_
#define BOAZ_CHROMIUM_NATIVE_PASSWORD_SUBMISSION_H_
#include <string>
#include "base/unguessable_token.h"
namespace content { class WebContents; class RenderFrameHost; }
namespace boaz {
base::UnguessableToken CaptureNativePasswordSubmission(
    content::WebContents*, content::RenderFrameHost*);
void CommitNativePasswordSubmission(content::WebContents*,
    const base::UnguessableToken&, const std::u16string&, const std::u16string&);
}
#endif
