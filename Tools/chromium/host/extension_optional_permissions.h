#ifndef BOAZ_EXTENSION_OPTIONAL_PERMISSIONS_H_
#define BOAZ_EXTENSION_OPTIONAL_PERMISSIONS_H_
#include <cstddef>
#include <memory>
#include "ui/gfx/native_ui_types.h"
#include "extensions/browser/extension_install_prompt_client.h"
class Profile;
class ExtensionFunction;
namespace boaz {
std::unique_ptr<extensions::ExtensionInstallPromptClient> CreateNativeOptionalPermissionsPrompt(
    Profile*, gfx::NativeWindow window, ExtensionFunction& requester);
void CancelNativeOptionalPermissionPrompts();
size_t PendingNativeOptionalPermissionPrompts();
}
#endif
