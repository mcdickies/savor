import SwiftUI

struct StarRatingView: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbol(for: index))
                    .foregroundColor(.yellow)
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(String(format: "%.1f", rating)) out of five stars")
    }

    private func symbol(for index: Int) -> String {
        let threshold = rating - Double(index)
        if threshold >= 1 { return "star.fill" }
        if threshold >= 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}
