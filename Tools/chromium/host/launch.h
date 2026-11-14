#ifndef BOAZ_CHROMIUM_LAUNCH_H_
#define BOAZ_CHROMIUM_LAUNCH_H_

#include <optional>
#include "base/files/file_path.h"

namespace boaz {
std::optional<base::FilePath> PackagedApplicationUserDataPath();
void ConfigurePackagedApplicationLaunch();
}  // namespace boaz
#endif
