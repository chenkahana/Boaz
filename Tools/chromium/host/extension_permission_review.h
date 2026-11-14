#ifndef BOAZ_EXTENSION_PERMISSION_REVIEW_H_
#define BOAZ_EXTENSION_PERMISSION_REVIEW_H_
#include <cstddef>
#include <string>
#include "extension_install.h"
namespace boaz {
bool StartExtensionPermissionReview(Profile*, void* nswindow, const std::string& id,
                                    base::OnceCallback<void(ExtensionInstallResult)>);
void CancelExtensionPermissionReviews();
size_t PendingExtensionPermissionReviews();
}
#endif
