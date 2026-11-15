#ifndef BOAZ_NATIVE_EXTENSION_UNINSTALL_DIALOG_H_
#define BOAZ_NATIVE_EXTENSION_UNINSTALL_DIALOG_H_
#include <memory>
#include "chrome/browser/extensions/extension_uninstall_dialog.h"
namespace boaz {
// The Remove confirmation as a sheet on the Boaz window, for chrome://extensions and the store.
std::unique_ptr<extensions::ExtensionUninstallDialog> CreateNativeExtensionUninstallDialog(
    Profile*, gfx::NativeWindow, extensions::ExtensionUninstallDialog::Delegate*);
}
#endif
