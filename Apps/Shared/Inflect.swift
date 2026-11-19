import Foundation

extension String {
    /// English with automatic grammar agreement, for copy that isn't a `Text`:
    /// `String(inflecting: "Archived ^[\(count) tab](inflect: true)")` gives "Archived 1 tab" and "Archived 2 tabs".
    /// docs/copy.md: no hand-built plurals.
    init(inflecting value: String.LocalizationValue) {
        self = String(AttributedString(localized: value).characters)
    }
}
