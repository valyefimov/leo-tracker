import SwiftUI

enum LeoTheme {
    static let green = Color(red: 0.08, green: 0.64, blue: 0.38)
    static let deepGreen = Color(red: 0.02, green: 0.28, blue: 0.18)
    static let surface = Color(nsColor: .controlBackgroundColor)
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(20)
            .background(LeoTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.07)))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 5)
    }
}
