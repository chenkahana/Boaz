#ifndef BOAZ_CHROMIUM_EXTENSION_UNPACKED_INSTALL_H_
#define BOAZ_CHROMIUM_EXTENSION_UNPACKED_INSTALL_H_
#include "extension_install.h"
namespace boaz {
bool InstallNativeUnpackedExtension(Profile*, void* parent, const base::FilePath&,
    base::OnceCallback<void(ExtensionInstallResult)>);
void CancelNativeUnpackedExtensionInstalls();
}
#endif
