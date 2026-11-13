#if BOAZ_CHROMIUM
import Foundation

struct ChromiumNetwork: Equatable {
    var offline = false
    var latencyMS = 0.0
    var downloadBytesPerSecond = -1.0
    var uploadBytesPerSecond = -1.0

    var isValid: Bool {
        func bandwidth(_ value: Double) -> Bool {
            value.isFinite && (value == -1 || (1...1_000_000_000).contains(value))
        }
        return latencyMS.isFinite && (0...10_000).contains(latencyMS) &&
            bandwidth(downloadBytesPerSecond) && bandwidth(uploadBytesPerSecond)
    }
    var native: BoazHostNetwork {
        BoazHostNetwork(latency_ms: latencyMS, download_bytes_per_second: downloadBytesPerSecond,
            upload_bytes_per_second: uploadBytesPerSecond, offline: offline ? 1 : 0)
    }
}
#endif
