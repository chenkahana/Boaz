#include "boaz/launch.h"

#import <Foundation/Foundation.h>

#include "base/apple/bundle_locations.h"
#include "base/check.h"
#include "base/check_op.h"
#include "base/command_line.h"

namespace boaz {
std::optional<base::FilePath> PackagedApplicationUserDataPath() {
  @autoreleasepool {
    NSBundle* bundle = base::apple::OuterBundle();
    NSString* identifier = bundle.bundleIdentifier;
    const bool development = [identifier isEqualToString:@"com.chenkahana.boaz.chromium.dev"];
    const bool production = [identifier isEqualToString:@"com.chenkahana.boaz"];
    id marker = [bundle objectForInfoDictionaryKey:@"BoazNativeApplication"];
    if (!marker && !development && !production) return std::nullopt;
    CHECK([marker isKindOfClass:[NSNumber class]] && [marker boolValue]);
    CHECK(development || production);
    NSString* expected_channel = development ? @"development" : @"production";
    id channel = [bundle objectForInfoDictionaryKey:@"BoazDistributionChannel"];
    CHECK([channel isKindOfClass:[NSString class]] && [channel isEqualToString:expected_channel]);
    NSString* product = development ? @"Boaz Chromium Development" : @"Boaz/Chromium";
    id configured_product = [bundle objectForInfoDictionaryKey:@"CrProductDirName"];
    CHECK([configured_product isKindOfClass:[NSString class]] && [configured_product isEqualToString:product]);
    NSArray<NSURL*>* roots = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                                  inDomains:NSUserDomainMask];
    CHECK_EQ(roots.count, 1u);
    NSURL* path = [roots.firstObject URLByAppendingPathComponent:product isDirectory:YES];
    CHECK(path.isFileURL);
    base::FilePath result(path.fileSystemRepresentation);
    CHECK(result.IsAbsolute());
    return result;
  }
}

void ConfigurePackagedApplicationLaunch() {
  auto* command = base::CommandLine::ForCurrentProcess();
  if (command->HasSwitch("type")) return;
  const auto expected = PackagedApplicationUserDataPath();
  if (!expected) return;
  if (command->HasSwitch("user-data-dir")) {
    CHECK(command->GetSwitchValuePath("user-data-dir").StripTrailingSeparators() == *expected);
  }
  if (command->HasSwitch("profile-directory")) {
    CHECK_EQ(command->GetSwitchValueASCII("profile-directory"), "Default");
  }
  for (const char* name : {"remote-debugging-port", "remote-debugging-pipe",
                           "remote-allow-origins", "remote-debugging-address",
                           "custom-devtools-frontend"}) {
    command->RemoveSwitch(name);
  }
  command->AppendSwitch("boaz-native-host");
  command->AppendSwitch("boaz-app-ui");
  command->AppendSwitch("no-startup-window");
  command->AppendSwitch("no-first-run");
  command->AppendSwitchASCII("profile-directory", "Default");
  command->AppendSwitchPath("user-data-dir", *expected);
}
}  // namespace boaz
