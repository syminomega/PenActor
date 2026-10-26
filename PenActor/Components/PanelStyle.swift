import SwiftUI

extension View {
    func panel() -> some View {
        padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.quaternary, lineWidth: 1))
    }
}
