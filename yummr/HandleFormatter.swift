import Foundation

enum HandleFormatter {
    static func normalizedHandle(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawValue }

        if trimmed.hasPrefix("@") {
            let sanitized = trimmed.drop(while: { $0 == "@" })
            return "@" + String(sanitized)
        }

        return "@" + trimmed
    }

    static func normalizedHandle(from optional: String?) -> String? {
        guard let optional else { return nil }
        let trimmed = optional.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return normalizedHandle(from: trimmed)
    }
}
