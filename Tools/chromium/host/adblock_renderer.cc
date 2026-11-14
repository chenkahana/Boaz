#include "adblock_renderer.h"
#include <optional>
#include "base/memory/weak_ptr.h"
#include "base/sequence_checker.h"
#include "base/strings/string_util.h"
#include "content/public/renderer/render_frame.h"
#include "content/public/renderer/render_frame_observer.h"
#include "content/public/renderer/render_frame_observer_tracker.h"
#include "third_party/blink/public/platform/web_security_origin.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/platform/web_url.h"
#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/public/web/web_script_source.h"
#include "url/gurl.h"
namespace boaz {
namespace {
class Observer final : public content::RenderFrameObserver,
                       public content::RenderFrameObserverTracker<Observer> {
 public:
  explicit Observer(content::RenderFrame* frame)
      : content::RenderFrameObserver(frame), content::RenderFrameObserverTracker<Observer>(frame) {}
  ~Observer() override = default;
  bool Matches(const blink::DocumentToken& token) const {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_);
    auto* frame = render_frame()->GetWebFrame();
    if (!frame || render_frame()->IsInFencedFrameTree()) return false;
    const auto document = frame->GetDocument();
    return !document.IsNull() && document.Token() == token &&
        !document.GetSecurityOrigin().IsOpaque() && GURL(document.Url()).SchemeIsHTTPOrHTTPS();
  }
  AdblockRendererResult Apply(const blink::DocumentToken& token, uint64_t generation,
                             std::string_view css, std::string_view script) {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_);
    if (!generation || css.size() > 1024 * 1024 || script.size() > 1024 * 1024 ||
        !base::IsStringUTF8(css) || !base::IsStringUTF8(script)) return AdblockRendererResult::kInvalid;
    if (!Matches(token)) return AdblockRendererResult::kUnavailable;
    if (!document_ || *document_ != token) Reset();
    document_ = token;
    if (generation < generation_) return AdblockRendererResult::kInvalid;
    if (generation == generation_) return script_executed_ && cleared_
        ? AdblockRendererResult::kRequiresReload : AdblockRendererResult::kUnchanged;
    generation_ = generation;
    cleared_ = false;
    auto document = render_frame()->GetWebFrame()->GetDocument();
    if (!style_key_.IsEmpty()) document.RemoveInsertedStyleSheet(style_key_, blink::WebCssOrigin::kUser);
    style_key_ = blink::WebString();
    if (!css.empty()) style_key_ = document.InsertStyleSheet(
        blink::WebString::FromUtf8(css), nullptr, blink::WebCssOrigin::kUser);
    if (script_executed_) return AdblockRendererResult::kRequiresReload;
    if (script.empty()) return AdblockRendererResult::kApplied;
    script_executed_ = true;
    auto weak = weak_.GetWeakPtr();
    render_frame()->GetWebFrame()->ExecuteScript(
        blink::WebScriptSource(blink::WebString::FromUtf8(script)));
    if (!weak || !weak->Matches(token)) return AdblockRendererResult::kUnavailable;
    return AdblockRendererResult::kApplied;
  }
  AdblockRendererResult Clear(const blink::DocumentToken& token) {
    DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_);
    if (!Matches(token)) return AdblockRendererResult::kUnavailable;
    if (!document_ || *document_ != token) return AdblockRendererResult::kUnchanged;
    if (!style_key_.IsEmpty()) render_frame()->GetWebFrame()->GetDocument().RemoveInsertedStyleSheet(
        style_key_, blink::WebCssOrigin::kUser);
    style_key_ = blink::WebString();
    cleared_ = true;
    return script_executed_ ? AdblockRendererResult::kRequiresReload : AdblockRendererResult::kApplied;
  }
 private:
  void Reset() {
    document_.reset(); style_key_ = blink::WebString(); generation_ = 0;
    script_executed_ = false; cleared_ = false;
  }
  // A cross-document commit discards the old document's CSS. BFCache entry and
  // restoration do not reset this state, preventing duplicate scriptlet effects.
  void DidCommitProvisionalLoad(ui::PageTransition) override { Reset(); }
  void OnDestruct() override { delete this; }
  std::optional<blink::DocumentToken> document_;
  blink::WebStyleSheetKey style_key_;
  uint64_t generation_ = 0;
  bool script_executed_ = false;
  bool cleared_ = false;
  SEQUENCE_CHECKER(sequence_);
  base::WeakPtrFactory<Observer> weak_{this};
};
}
void InitializeAdblockRenderer(content::RenderFrame* frame) {
  if (frame && !Observer::Get(frame)) new Observer(frame);
}
AdblockRendererResult ApplyAdblockRenderer(content::RenderFrame* frame,
    const blink::DocumentToken& token, uint64_t generation, std::string_view css,
    std::string_view script) {
  auto* observer = frame ? Observer::Get(frame) : nullptr;
  return observer ? observer->Apply(token, generation, css, script) : AdblockRendererResult::kUnavailable;
}
AdblockRendererResult ClearAdblockRenderer(content::RenderFrame* frame, const blink::DocumentToken& token) {
  auto* observer = frame ? Observer::Get(frame) : nullptr;
  return observer ? observer->Clear(token) : AdblockRendererResult::kUnavailable;
}
}
