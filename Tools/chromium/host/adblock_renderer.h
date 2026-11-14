#ifndef BOAZ_ADBLOCK_RENDERER_H_
#define BOAZ_ADBLOCK_RENDERER_H_
#include <cstdint>
#include <string_view>
#include "third_party/blink/public/common/tokens/tokens.h"
namespace content { class RenderFrame; }
namespace boaz {
enum class AdblockRendererResult { kApplied, kUnchanged, kRequiresReload, kInvalid, kUnavailable };
// Renderer-main-thread internal calls only, never exposed to page JavaScript.
void InitializeAdblockRenderer(content::RenderFrame*);
AdblockRendererResult ApplyAdblockRenderer(content::RenderFrame*, const blink::DocumentToken&,
    uint64_t generation, std::string_view static_css, std::string_view public_script);
AdblockRendererResult ClearAdblockRenderer(content::RenderFrame*, const blink::DocumentToken&);
}
#endif
