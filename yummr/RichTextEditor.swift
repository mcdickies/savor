import SwiftUI
import UIKit

struct RichTextEditor: UIViewRepresentable {
    @Binding var text: AttributedString

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        textView.smartDashesType = .yes
        textView.smartQuotesType = .yes
        textView.smartInsertDeleteType = .yes
        textView.attributedText = NSAttributedString(text)
        applyTypingAttributes(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let current = AttributedString(textView.attributedText)
        if current != text {
            let selectedRange = textView.selectedRange
            let attributed = NSAttributedString(text)
            textView.attributedText = attributed
            let maxLocation = attributed.length
            let clampedLocation = min(selectedRange.location, maxLocation)
            let clampedLength = min(selectedRange.length, maxLocation - clampedLocation)
            textView.selectedRange = NSRange(location: clampedLocation, length: clampedLength)
        }
        applyTypingAttributes(to: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func applyTypingAttributes(to textView: UITextView) {
        let font = UIFont.preferredFont(forTextStyle: .body)
        textView.typingAttributes[.font] = font
        textView.typingAttributes[.foregroundColor] = UIColor.label
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor

        init(parent: RichTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = AttributedString(textView.attributedText)
        }
    }
}

extension AttributedString {
    var plainText: String { String(characters) }
}
