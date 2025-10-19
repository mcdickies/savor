import Foundation

enum HandleFormatter {
    private static func normalizedHandleValue(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawValue }

        if trimmed.hasPrefix("@") {
            let sanitized = trimmed.drop(while: { $0 == "@" })
            return "@" + String(sanitized)
        }

        return "@" + trimmed
    }

    static func normalizedHandle(from rawValue: String) -> String {
        normalizedHandleValue(from: rawValue)
    }

    static func normalizedHandle(from optional: String?) -> String? {
        guard let optional else { return nil }
        let trimmedValue = optional.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }
        return normalizedHandleValue(from: trimmedValue)
    }
}
