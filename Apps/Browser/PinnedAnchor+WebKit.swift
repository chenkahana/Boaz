import Foundation
import WebKit

extension PinnedAnchor {
    static func hasWandered(_ page: WebPage, from saved: URL?) -> Bool {
        hasWandered(current: page.url, saved: saved,
                    landing: page.backForwardList.backList.first?.url)
    }
}
