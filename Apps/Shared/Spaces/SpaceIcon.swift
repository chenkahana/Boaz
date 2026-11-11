import BoazKit
import SwiftUI

/// Emoji or SF Symbol space icon.
struct SpaceIcon: View {
    let space: Space
    var size: CGFloat = 16

    var body: some View {
        let icon = space.icon ?? "✦"
        if icon.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }) {
            Image(systemName: icon).font(.system(size: size * 0.85, weight: .semibold))
        } else {
            Text(icon).font(.system(size: size))
        }
    }
}
