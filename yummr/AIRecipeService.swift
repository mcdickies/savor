import Foundation
import UIKit

struct AIRecipeDraft: Codable {
    let title: String?
    let summary: String?
    let description: String?
    let ingredients: [String]?
    let instructions: [String]?
    let notes: [String]?
    let recipe: String?

    private enum CodingKeys: String, CodingKey {
        case title
        case summary
        case description
        case ingredients
        case instructions
        case notes
        case recipe
    }
}

final class AIRecipeService {
    static let shared = AIRecipeService()

    enum ServiceError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case invalidResponse
        case emptyResponse
        case decodingFailed
        case api(message: String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add a Gemini API key in Settings to draft with AI."
            case .invalidURL, .invalidResponse:
                return "Unable to reach the Gemini service right now. Please try again."
            case .emptyResponse:
                return "Gemini returned an empty response. Try adjusting your prompt and sending again."
            case .decodingFailed:
                return "Gemini sent back an unexpected format. Try regenerating your draft."
            case .api(let message):
                return message
            }
        }
    }

    private struct GeminiRequest: Encodable {
        struct Content: Encodable {
            let role: String
            let parts: [Part]
        }

        struct Part: Encodable {
            let text: String?
            let inlineData: InlineData?

            enum CodingKeys: String, CodingKey {
                case text
                case inlineData
            }
        }

        struct InlineData: Encodable {
            let mimeType: String
            let data: String
        }

        struct GenerationConfig: Encodable {
            let temperature: Double
            let topP: Double
            let responseMimeType: String
        }

        let contents: [Content]
        let generationConfig: GenerationConfig
    }

    private struct GeminiResponse: Decodable {
        struct Candidate: Decodable {
            struct CandidateContent: Decodable {
                struct Part: Decodable {
                    let text: String?
                }

                let parts: [Part]
            }

            let content: CandidateContent
            let finishReason: String?
        }

        let candidates: [Candidate]?
    }

    private struct GeminiAPIErrorEnvelope: Decodable {
        struct GeminiAPIError: Decodable {
            let message: String
        }

        let error: GeminiAPIError
    }

    private static let apiKeyKey = "ai.gemini.apiKey"
    private let session: URLSession
    private let modelName = "gemini-1.5-flash"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateDraft(
        currentTitle: String,
        currentDescription: String,
        currentRecipe: String,
        transcript: String,
        capturedIdeas: [String],
        customPrompt: String,
        ingredients: [String],
        images: [UIImage]
    ) async throws -> AIRecipeDraft {
        guard let apiKey = loadAPIKey() else { throw ServiceError.missingAPIKey }
        let endpoint = "\(baseURL)/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else { throw ServiceError.invalidURL }

        let requestBody = try makeRequestBody(
            title: currentTitle,
            description: currentDescription,
            recipe: currentRecipe,
            transcript: transcript,
            capturedIdeas: capturedIdeas,
            customPrompt: customPrompt,
            ingredients: ingredients,
            images: images
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = requestBody

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(GeminiAPIErrorEnvelope.self, from: data) {
                throw ServiceError.api(message: apiError.error.message)
            }
            throw ServiceError.invalidResponse
        }

        guard let text = try extractTextPayload(from: data) else { throw ServiceError.emptyResponse }
        guard let jsonData = text.data(using: .utf8) else { throw ServiceError.decodingFailed }

        do {
            return try JSONDecoder().decode(AIRecipeDraft.self, from: jsonData)
        } catch {
            throw ServiceError.decodingFailed
        }
    }

    private func loadAPIKey() -> String? {
        if let key = KeychainHelper.load(Self.apiKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }

        if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !envKey.isEmpty {
            return envKey
        }

        return nil
    }

    private func makeRequestBody(
        title: String,
        description: String,
        recipe: String,
        transcript: String,
        capturedIdeas: [String],
        customPrompt: String,
        ingredients: [String],
        images: [UIImage]
    ) throws -> Data {
        let infoSections = buildInfoSections(
            title: title,
            description: description,
            recipe: recipe,
            transcript: transcript,
            capturedIdeas: capturedIdeas,
            customPrompt: customPrompt,
            ingredients: ingredients
        )

        var parts: [GeminiRequest.Part] = [
            GeminiRequest.Part(text: infoSections, inlineData: nil)
        ]

        let encodedImages: [GeminiRequest.Part] = images
            .prefix(4)
            .compactMap { image in
                guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }
                let base64 = data.base64EncodedString()
                let inline = GeminiRequest.InlineData(mimeType: "image/jpeg", data: base64)
                return GeminiRequest.Part(text: nil, inlineData: inline)
            }

        parts.append(contentsOf: encodedImages)

        let request = GeminiRequest(
            contents: [
                GeminiRequest.Content(
                    role: "user",
                    parts: parts
                )
            ],
            generationConfig: GeminiRequest.GenerationConfig(
                temperature: 0.6,
                topP: 0.95,
                responseMimeType: "application/json"
            )
        )

        return try JSONEncoder().encode(request)
    }

    private func buildInfoSections(
        title: String,
        description: String,
        recipe: String,
        transcript: String,
        capturedIdeas: [String],
        customPrompt: String,
        ingredients: [String]
    ) -> String {
        var sections: [String] = []

        sections.append("You are an assistant that turns loose cooking notes into a publishable recipe for the Yummr app.")
        sections.append("Use the following inputs to craft a concise recipe draft.")
        sections.append("Return only JSON with this structure (replace the placeholders with real values): {\"title\": \"...\", \"summary\": \"...\", \"ingredients\": [\"...\"], \"instructions\": [\"...\"], \"notes\": [\"...\"], \"recipe\": \"...\" }.")
        sections.append("Do not include markdown, explanations, or any text outside of that JSON object.")

        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Current title: \(title)")
        }

        if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Post description context: \(description)")
        }

        if !recipe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Existing recipe draft: \(recipe)")
        }

        if !ingredients.isEmpty {
            sections.append("Ingredients to highlight: \(ingredients.joined(separator: ", "))")
        }

        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Voice memo transcript: \(transcript)")
        }

        if !capturedIdeas.isEmpty {
            let ideasText = capturedIdeas.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " \u2022 ")
            sections.append("Saved brainstorming ideas: \(ideasText)")
        }

        if !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Author guidance: \(customPrompt)")
        }

        sections.append("Keep instructions actionable and short. Respect any cook times or key flavors mentioned. If information is missing, make reasonable assumptions but keep them labeled as notes.")

        return sections.joined(separator: "\n\n")
    }

    private func extractTextPayload(from data: Data) throws -> String? {
        let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let candidate = response.candidates?.first else { return nil }
        let combined = candidate.content.parts.compactMap { $0.text }.joined(separator: "\n")
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
