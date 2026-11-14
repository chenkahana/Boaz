#ifndef BOAZ_CHROMIUM_NATIVE_COOKIE_IMPORT_H_
#define BOAZ_CHROMIUM_NATIVE_COOKIE_IMPORT_H_

#include <stddef.h>
#include <stdint.h>
#include "base/functional/callback.h"
#include "boaz_host.h"

namespace content { class BrowserContext; }

namespace boaz {
using CookieImportCompletion = base::OnceCallback<void(uint32_t imported, uint32_t rejected)>;
// UI-thread only. Copies input synchronously; posts exactly one completion after every set.
void ImportNativeCookies(content::BrowserContext* context, const BoazHostCookie* cookies,
                         size_t count, CookieImportCompletion completion);
}  // namespace boaz
#endif
