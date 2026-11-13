#if BOAZ_CHROMIUM
import Foundation

struct ChromiumSensors: Equatable {
    struct Geolocation: Equatable {
        var latitude: Double
        var longitude: Double
        var accuracy: Double

        var isValid: Bool {
            latitude.isFinite && longitude.isFinite && accuracy.isFinite &&
                (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
                (0...1_000_000).contains(accuracy)
        }
    }

    var location: Geolocation?
    var timezone = ""
    var locale = ""

    var isValid: Bool {
        location?.isValid != false && [timezone, locale].allSatisfy {
            $0.utf8.count <= 128 && $0.utf8.allSatisfy { (32...126).contains($0) }
        }
    }
}
#endif
