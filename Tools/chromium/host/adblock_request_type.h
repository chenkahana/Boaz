#ifndef BOAZ_ADBLOCK_REQUEST_TYPE_H_
#define BOAZ_ADBLOCK_REQUEST_TYPE_H_
#include <optional>
#include <string_view>
#include "services/network/public/mojom/fetch_api.mojom-shared.h"
namespace boaz {
// Unknown enum values or contradictory typed destinations are unavailable.
std::optional<std::string_view> AdblockRequestType(
    int resource_type, network::mojom::RequestDestination destination);
}
#endif
