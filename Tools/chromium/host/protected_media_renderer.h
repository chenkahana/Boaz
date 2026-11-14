#ifndef BOAZ_PROTECTED_MEDIA_RENDERER_H_
#define BOAZ_PROTECTED_MEDIA_RENDERER_H_

#include <string>

namespace content {
class RenderFrame;
}

namespace boaz {

void ObserveKeySystemRequest(content::RenderFrame* frame,
                             const std::string& key_system);

}  // namespace boaz

#endif  // BOAZ_PROTECTED_MEDIA_RENDERER_H_
