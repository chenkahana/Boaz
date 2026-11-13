#ifndef BOAZ_CHROMIUM_NATIVE_LOCATION_BAR_H_
#define BOAZ_CHROMIUM_NATIVE_LOCATION_BAR_H_

#include <memory>
#include "base/functional/callback.h"
class BrowserWindowInterface;
class LocationBar;
namespace boaz {
// Provider returns the stable, UI-owned, attached NSTextField. UI thread only.
struct NativeLocationBarDeleter {
  void operator()(LocationBar* bar) const;
};
using NativeLocationBarPtr = std::unique_ptr<LocationBar, NativeLocationBarDeleter>;
NativeLocationBarPtr CreateNativeLocationBar(
    BrowserWindowInterface* browser, base::RepeatingCallback<void*()> field);
}
#endif
