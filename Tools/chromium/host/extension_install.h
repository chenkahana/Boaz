#ifndef BOAZ_CHROMIUM_EXTENSION_INSTALL_H_
#define BOAZ_CHROMIUM_EXTENSION_INSTALL_H_
#include "base/files/file_path.h"
#include "base/functional/callback.h"
class Profile;
namespace boaz {
enum class ExtensionInstallResult { kInstalled, kCancelled, kFailed };
bool InstallNativeExtension(Profile*, void* native_parent, const base::FilePath&,
                            base::OnceCallback<void(ExtensionInstallResult)>);
void CancelNativeExtensionInstalls();
}
#endif
