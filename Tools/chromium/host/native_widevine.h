#ifndef BOAZ_CHROMIUM_NATIVE_WIDEVINE_H_
#define BOAZ_CHROMIUM_NATIVE_WIDEVINE_H_

#include <string>
#include "boaz_host.h"

namespace boaz {
// UI-thread only. READY means an installed CDM that passed the Google signature check, which runs in the background.
BoazHostWidevineState NativeWidevineState(std::string* version);
}  // namespace boaz
#endif
