import SwiftUI
import UIKit

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

    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
