//
//  UserService 2.swift
//  yummr
//
//  Created by kuba woahz on 9/15/25.
//


import Foundation
import FirebaseFirestore

final class UserService: ObservableObject {
    static let shared = UserService()
    private let db = Firestore.firestore()

    func searchUsers(matching query: String, limit: Int = 20, completion: @escaping ([AppUser]) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion([])
            return
        }

        db.collection("users")
            .limit(to: max(limit, 1))
            .getDocuments { snapshot, error in
                guard error == nil, let documents = snapshot?.documents else {
                    completion([])
                    return
                }

                let lowercasedQuery = trimmed.lowercased()
                let users: [AppUser] = documents.compactMap { try? $0.data(as: AppUser.self) }
                    .filter { user in
                        let handleMatch = user.handle.lowercased().contains(lowercasedQuery)
                        let displayMatch = user.displayName.lowercased().contains(lowercasedQuery)
                        let bioMatch = (user.bio ?? "").lowercased().contains(lowercasedQuery)
                        return handleMatch || displayMatch || bioMatch
                    }

                completion(Array(users.prefix(limit)))
            }
    }

    func fetchUsers(withIDs ids: [String], completion: @escaping ([AppUser]) -> Void) {
        guard !ids.isEmpty else {
            completion([])
            return
        }

        let uniqueIDs = Array(Set(ids))
        var fetched: [AppUser] = []
        let group = DispatchGroup()

        for chunk in uniqueIDs.chunked(into: 10) {
            group.enter()
            db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments { snapshot, _ in
                    if let documents = snapshot?.documents {
                        let users = documents.compactMap { try? $0.data(as: AppUser.self) }
                        fetched.append(contentsOf: users)
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            completion(fetched)
        }
    }

    func fetchUser(withID id: String, completion: @escaping (AppUser?) -> Void) {
        db.collection("users").document(id).getDocument { snapshot, _ in
            completion(try? snapshot?.data(as: AppUser.self))
        }
    }

    func fetchUser(withHandle handle: String, completion: @escaping (AppUser?) -> Void) {
        db.collection("users")
            .whereField("handle", isEqualTo: handle)
            .limit(to: 1)
            .getDocuments { snapshot, _ in
                guard let document = snapshot?.documents.first else {
                    completion(nil)
                    return
                }
                completion(try? document.data(as: AppUser.self))
            }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}
