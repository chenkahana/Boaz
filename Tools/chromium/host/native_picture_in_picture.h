#ifndef BOAZ_NATIVE_PICTURE_IN_PICTURE_H_
#define BOAZ_NATIVE_PICTURE_IN_PICTURE_H_
#include "base/functional/callback_forward.h"
namespace content { class VideoPictureInPictureWindowController; }
namespace views { class Widget; }
namespace boaz {
// Whether Boaz draws the video Picture in Picture controls itself; Chromium's own controls stay hidden then.
bool NativePictureInPictureControlsEnabled();
// Gives Chromium's video Picture in Picture window Boaz's native controls and keeps it above every window on every
// Space and display. The controls live as long as `window`. `overlay_shown` reports Chromium's own permission overlay,
// which the controls make way for.
void AttachNativePictureInPictureControls(views::Widget* window,
                                          content::VideoPictureInPictureWindowController* controller,
                                          base::RepeatingCallback<bool()> overlay_shown);
}
#endif
