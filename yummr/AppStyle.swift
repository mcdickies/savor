import SwiftUI

struct AppFontModifier: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content
            .font(.system(style, design: .rounded))
            .fontWeight(weight)
    }
}

extension View {
    func appTextStyle(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(AppFontModifier(style: style, weight: weight))
    }
}
