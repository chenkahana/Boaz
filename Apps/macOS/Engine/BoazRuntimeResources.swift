#if BOAZ_CHROMIUM
import Foundation

enum BoazRuntimeResources {
    static let bundle: Bundle = {
        guard let resources = Bundle.main.resourceURL,
              let bundle = Bundle(url: resources.appendingPathComponent("BoazResources.bundle", isDirectory: true)) else {
            preconditionFailure("BoazResources.bundle is missing from the Chromium application's Resources directory.")
        }
        return bundle
    }()
}
#endif
