#ifndef BOAZ_NATIVE_EXTENSION_PROMPT_H_
#define BOAZ_NATIVE_EXTENSION_PROMPT_H_
#include <cstddef>
#include <memory>
#include "extensions/browser/extension_install_prompt_client.h"
class ExtensionInstallPromptShowParams;
class Profile;
namespace extensions { class InstallPromptData; }
namespace boaz {
bool IsNativeExtensionPromptContext(Profile*, void* nswindow);
void NativeExtensionPromptsChanged();
void ShowNativeExtensionPrompt(
    std::unique_ptr<ExtensionInstallPromptShowParams>,
    extensions::ExtensionInstallPromptClient::DoneCallback,
    std::unique_ptr<extensions::InstallPromptData>);
void CancelNativeExtensionPrompts();
size_t PendingNativeExtensionPrompts();
}
#endif
