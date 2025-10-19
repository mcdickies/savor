import Foundation
import FirebaseFirestore

final class SecretsService: ObservableObject {
    static let shared = SecretsService()

    private let db = Firestore.firestore()
    private lazy var sharedSecretsReference = db.collection("appConfig").document("publicSecrets")
    private let keychainKey = "ai.gemini.apiKey"
    private var cachedGeminiKey: String?

    private init() {
        if let existing = KeychainHelper.load(keychainKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            cachedGeminiKey = existing
        }
    }

    func cachedGeminiAPIKey() -> String? {
        if let cached = cachedGeminiKey, !cached.isEmpty {
            return cached
        }

        if let stored = KeychainHelper.load(keychainKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            cachedGeminiKey = stored
            return stored
        }

        return nil
    }

    func resolveSharedGeminiAPIKey() async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            self.sharedSecretsReference.getDocument { snapshot, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data = snapshot?.data(),
                      let rawKey = data["geminiAPIKey"] as? String,
                      let sanitized = self.sanitizedGeminiKey(from: rawKey) else {
                    continuation.resume(returning: nil)
                    return
                }

                self.cacheGeminiAPIKey(sanitized)
                continuation.resume(returning: sanitized)
            }
        }
    }

    func cacheGeminiAPIKey(_ key: String) {
        guard let sanitized = sanitizedGeminiKey(from: key) else { return }
        KeychainHelper.save(keychainKey, sanitized)
        cachedGeminiKey = sanitized
    }

    private func sanitizedGeminiKey(from rawValue: String?) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
