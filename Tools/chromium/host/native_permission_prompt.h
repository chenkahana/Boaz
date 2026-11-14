#ifndef BOAZ_CHROMIUM_NATIVE_PERMISSION_PROMPT_H_
#define BOAZ_CHROMIUM_NATIVE_PERMISSION_PROMPT_H_
#include <memory>
#include "components/permissions/permission_prompt.h"
namespace boaz {
std::unique_ptr<permissions::PermissionPrompt> CreateNativePermissionPrompt(
    content::WebContents* contents,
    permissions::PermissionPrompt::Delegate* delegate);
}
#endif
