#include "adblock_request_type.h"
#include "third_party/blink/public/mojom/loader/resource_load_info.mojom-shared.h"
namespace boaz {
std::optional<std::string_view> AdblockRequestType(
    int resource_type, network::mojom::RequestDestination destination) {
  using R = blink::mojom::ResourceType;
  std::string_view kind;
  // Switch on integers so out-of-range inputs never become unchecked enums.
  switch (resource_type) {
    case static_cast<int>(R::kMainFrame):
    case static_cast<int>(R::kNavigationPreloadMainFrame): kind = "document"; break;
    case static_cast<int>(R::kSubFrame):
    case static_cast<int>(R::kNavigationPreloadSubFrame): kind = "subdocument"; break;
    case static_cast<int>(R::kStylesheet): kind = "stylesheet"; break;
    case static_cast<int>(R::kScript):
    case static_cast<int>(R::kWorker):
    case static_cast<int>(R::kSharedWorker):
    case static_cast<int>(R::kServiceWorker): kind = "script"; break;
    case static_cast<int>(R::kImage):
    case static_cast<int>(R::kFavicon): kind = "image"; break;
    case static_cast<int>(R::kFontResource): kind = "font"; break;
    case static_cast<int>(R::kObject):
    case static_cast<int>(R::kPluginResource): kind = "object"; break;
    case static_cast<int>(R::kMedia): kind = "media"; break;
    case static_cast<int>(R::kXhr): kind = "xmlhttprequest"; break;
    case static_cast<int>(R::kPing): kind = "ping"; break;
    case static_cast<int>(R::kCspReport): kind = "csp_report"; break;
    case static_cast<int>(R::kSubResource):
    case static_cast<int>(R::kPrefetch):
    case static_cast<int>(R::kJson): kind = "other"; break;
    default: return std::nullopt;
  }
  using D = network::mojom::RequestDestination;
  std::string_view destination_kind;
  switch (destination) {
    case D::kEmpty:
      // Empty destination does not mean XHR. Its explicit resource type wins;
      // zero-initialized/default main-frame classification is not sufficient.
      return kind == "document" || kind == "subdocument" ? std::nullopt : std::optional(kind);
    case D::kDocument: destination_kind = "document"; break;
    case D::kFrame: case D::kIframe: case D::kFencedframe: destination_kind = "subdocument"; break;
    case D::kStyle: case D::kXslt: destination_kind = "stylesheet"; break;
    case D::kScript: case D::kWorker: case D::kSharedWorker: case D::kServiceWorker:
    case D::kAudioWorklet: case D::kPaintWorklet: destination_kind = "script"; break;
    case D::kImage: destination_kind = "image"; break;
    case D::kFont: destination_kind = "font"; break;
    case D::kAudio: case D::kVideo: case D::kTrack: destination_kind = "media"; break;
    case D::kEmbed: case D::kObject: destination_kind = "object"; break;
    case D::kReport:
      return kind == "csp_report" || kind == "ping" ? std::optional(kind) : std::nullopt;
    case D::kManifest: case D::kWebBundle: case D::kWebIdentity:
    case D::kCompressionDictionary: case D::kSpeculationRules: case D::kJson:
    case D::kEmailVerification: case D::kText: destination_kind = "other"; break;
    default: return std::nullopt;
  }
  if (kind != destination_kind) return std::nullopt;
  return kind;
}
}
