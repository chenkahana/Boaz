#ifndef BOAZ_NATIVE_EXTENSION_STORE_DIALOGS_H_
#define BOAZ_NATIVE_EXTENSION_STORE_DIALOGS_H_
#include <cstddef>
#include <string>
#include "base/functional/callback.h"
namespace content { class WebContents; }
namespace boaz {
void ShowNativeExtensionBlocked(content::WebContents*, std::string name,
                               std::string id, std::u16string admin_message,
                               base::OnceClosure);
void ShowNativeExtensionParentApprovalUnavailable(content::WebContents*, base::OnceClosure);
void ShowNativeExtensionFriction(content::WebContents*, base::OnceCallback<void(bool)>);
size_t PendingNativeExtensionStoreDialogs();
void CancelNativeExtensionStoreDialogs();
}
#endif
