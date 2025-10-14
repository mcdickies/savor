import Foundation

extension Post {
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
        return "\(calories) kcal"
    }

    var notesList: [String] {
        let raw = extraFields?["notes"] ?? extraFields?["aiNotes"] ?? ""
        return parseList(from: raw)
    }

    var ingredientList: [String] {
        guard let raw = extraFields?["ingredients"] else { return [] }
        return parseList(from: raw)
    }

    var instructionsList: [String] {
        guard let recipe else { return [] }
        return recipe
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
            .components(separatedBy: CharacterSet(charactersIn: ",\n•"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
