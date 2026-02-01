import Foundation

extension Post {
    /// Returns a stable identifier for the post even when the Firestore document ID is unavailable.
    var stableIdentifier: String {
        if let id = id, !id.isEmpty {
            return id
        }

        let sanitizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let timestampComponent = String(Int(timestamp.timeIntervalSince1970 * 1000))
        return "\(sanitizedTitle)-\(timestampComponent)"
    }

    var starRating: Double? {
        parseDouble(forKeys: ["rating", "starRating", "stars"])
    }

    var isFavorited: Bool {
        guard let value = extraFields?["isFavorite"] ?? extraFields?["favorite"] else {
            return false
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "true" || normalized == "1" || normalized == "yes"
    }

    var calorieEstimate: Int? {
        guard let raw = extraFields?["calorieEstimate"] ?? extraFields?["calories"] else {
            return nil
        }
        let digits = raw.compactMap { $0.isNumber ? $0 : nil }
        guard let parsed = Int(String(digits)) else { return nil }
        return parsed
    }

    var formattedCalories: String? {
        guard let calories = calorieEstimate else { return nil }
        return "\(calories) calories"
    }

    var cleanedCookTime: String? {
        guard let cookTime, !cookTime.isEmpty else { return nil }
        let cleaned = strippingCreativeTags(from: cookTime)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    var notesList: [String] {
        let raw = extraFields?["notes"] ?? extraFields?["aiNotes"] ?? ""
        return parseList(from: raw)
    }

    var youtubeLink: String? {
        guard let link = extraFields?["youtubeLink"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !link.isEmpty else { return nil }
        return link
    }

    var youtubeTitle: String? {
        guard let title = extraFields?["youtubeTitle"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        return title
    }

    var ingredientList: [String] {
        guard let raw = extraFields?["ingredients"] else { return [] }
        return parseList(from: raw)
    }

    var instructionsList: [String] {
        guard let recipe else { return [] }
        return strippingCreativeTags(from: recipe)
            .components(separatedBy: CharacterSet.newlines)
            .map { sanitizeInstruction($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    var cleanedRecipeText: String? {
        guard let recipe else { return nil }
        let cleaned = strippingCreativeTags(from: recipe)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cleaned
    }

    private func parseDouble(forKeys keys: [String]) -> Double? {
        for key in keys {
            if let value = extraFields?[key] {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let number = Double(trimmed) {
                    return number
                }
                let digits = trimmed.compactMap { $0.isNumber ? $0 : ($0 == "." ? $0 : nil) }
                if let number = Double(String(digits)) {
                    return number
                }
            }
        }
        return nil
    }

    private func parseList(from string: String) -> [String] {
        string
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { strippingCreativeTags(from: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func sanitizeInstruction(_ step: String) -> String {
        let cleaned = strippingCreativeTags(from: step)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func strippingCreativeTags(from text: String) -> String {
        text
            .replacingOccurrences(of: "<creative>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "</creative>", with: "", options: .caseInsensitive)
    }
}
