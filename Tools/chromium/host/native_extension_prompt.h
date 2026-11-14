#ifndef BOAZ_NATIVE_EXTENSION_PROMPT_H_
#define BOAZ_NATIVE_EXTENSION_PROMPT_H_
#include <cstddef>
#include <cstdint>
#include <memory>
#include "extensions/browser/extension_install_prompt_client.h"
class ExtensionInstallPromptShowParams;
class Profile;
namespace extensions { class InstallPromptData; }
namespace boaz {
bool IsNativeExtensionPromptContext(Profile*, void* nswindow);
void NativeExtensionPromptsChanged();
uint64_t ShowNativeExtensionPrompt(
    std::unique_ptr<ExtensionInstallPromptShowParams>,
    extensions::ExtensionInstallPromptClient::DoneCallback,
    std::unique_ptr<extensions::InstallPromptData>);
void CancelNativeExtensionPrompt(uint64_t token);
void CancelNativeExtensionPrompts();
size_t PendingNativeExtensionPrompts();
}
#endif
