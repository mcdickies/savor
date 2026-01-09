//
//  UserService 2.swift
//  yummr
//
//  Created by kuba woahz on 9/15/25.
//


import Foundation
import FirebaseAuth
import FirebaseFirestore


final class UserService: ObservableObject {
    static let shared = UserService()
    private let db = Firestore.firestore()

    func ensureUserDocument(for user: User,
                             displayName overrideDisplayName: String? = nil,
                             completion: ((Error?) -> Void)? = nil) {
        let userRef = db.collection("users").document(user.uid)

        userRef.getDocument { snapshot, error in
            if let error = error {
                completion?(error)
                return
            }

            let existingData = snapshot?.data() ?? [:]

            let trimmedOverride = overrideDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let overrideName = (trimmedOverride?.isEmpty ?? true) ? nil : trimmedOverride
            let resolvedDisplayName: String
            if let overrideName = overrideName {
                resolvedDisplayName = overrideName
            } else if let name = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                resolvedDisplayName = name
            } else if let email = user.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
                resolvedDisplayName = email
            } else {
                resolvedDisplayName = "New Chef"
            }

            let normalizedHandle = HandleFormatter.normalizedHandle(from: resolvedDisplayName)
            let strippedHandle = String(normalizedHandle.drop(while: { $0 == "@" }))
            let storedHandle = strippedHandle.isEmpty ? normalizedHandle : strippedHandle

            var payload: [String: Any] = [:]

            let existingDisplayName = (existingData["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let overrideName = overrideName, overrideName != existingDisplayName {
                payload["displayName"] = overrideName
            } else if existingDisplayName?.isEmpty ?? true {
                payload["displayName"] = resolvedDisplayName
            }

            let existingHandle = (existingData["handle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if existingHandle?.isEmpty ?? true {
                payload["handle"] = storedHandle
            }

            if existingData["notificationSettings"] == nil {
                payload["notificationSettings"] = [
                    "likes": true,
                    "comments": true,
                    "friendRequests": true,
                    "friendPosts": true,
                    "mutedUserIDs": []
                ]
            }

            if existingData["privacySettings"] == nil {
                payload["privacySettings"] = [
                    "isPrivateAccount": false,
                    "allowContactDiscovery": true
                ]
            }

            if existingData["followerCount"] == nil {
                payload["followerCount"] = 0
            }

            if existingData["followingCount"] == nil {
                payload["followingCount"] = 0
            }

            if existingData["topFoods"] == nil {
                payload["topFoods"] = []
            }

            if existingData["healthMetrics"] == nil {
                payload["healthMetrics"] = [:]
            }

            if existingData["bio"] == nil {
                payload["bio"] = ""
            }

            if existingData["profileImageURL"] == nil, let url = user.photoURL?.absoluteString, !url.isEmpty {
                payload["profileImageURL"] = url
            }

            if existingData["phoneNumber"] == nil, let phone = user.phoneNumber, !phone.isEmpty {
                payload["phoneNumber"] = phone
            }

            if existingData["friendIDs"] == nil {
                payload["friendIDs"] = []
            }

            if existingData["pendingFriendRequestIDs"] == nil {
                payload["pendingFriendRequestIDs"] = []
            }

            if payload.isEmpty {
                SavedService.shared.ensureDefaultCollection(for: user.uid)
                completion?(nil)
                return
            }

            userRef.setData(payload, merge: true) { error in
                if error == nil {
                    SavedService.shared.ensureDefaultCollection(for: user.uid)
                }
                completion?(error)
            }
        }
    }

    func updateProfileImage(uid: String, url: String, completion: ((Error?) -> Void)? = nil) {
        db.collection("users")
            .document(uid)
            .setData(["profileImageURL": url], merge: true, completion: completion)
    }

    func searchUsers(matching query: String,
                     limit: Int = 20,
                     includeBio: Bool = true,
                     completion: @escaping ([AppUser]) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion([])
            return
        }

        let normalizedQuery: String
        if trimmed.hasPrefix("@") {
            let stripped = String(trimmed.drop(while: { $0 == "@" }))
            normalizedQuery = stripped.isEmpty ? trimmed : stripped
        } else {
            normalizedQuery = trimmed
        }

        db.collection("users")
            .limit(to: max(limit * 3, 25))
            .getDocuments { snapshot, error in
                guard error == nil, let documents = snapshot?.documents else {
                    completion([])
                    return
                }

     
                let lowercasedQuery = normalizedQuery.lowercased()
                let users: [AppUser] = documents.compactMap { document in
                    guard var user = try? document.data(as: AppUser.self) else { return nil }
                    if user.id == nil {
                        user.id = document.documentID
                    }
                    return user
                }
                    .sorted { ($0.displayName.lowercased(), $0.handle.lowercased()) < ($1.displayName.lowercased(), $1.handle.lowercased()) }
                    .filter { user in
                        let handle = user.handle.lowercased()
                        let display = user.displayName.lowercased()
                        let bio = (user.bio ?? "").lowercased()

                        if handle.hasPrefix(lowercasedQuery) || display.hasPrefix(lowercasedQuery) {
                            return true
                        }

                        if handle.contains(lowercasedQuery) || display.contains(lowercasedQuery) {
                            return true
                        }

                        if includeBio {
                            return bio.contains(lowercasedQuery)
                        }

                        return false
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

    func deleteAccount(uid: String, completion: ((Error?) -> Void)? = nil) {
        let userRef = db.collection("users").document(uid)
        userRef.delete { error in
            if let error = error {
                completion?(error)
                return
            }

            self.db.collection("posts")
                .whereField("authorID", isEqualTo: uid)
                .getDocuments { snapshot, _ in
                    guard let docs = snapshot?.documents else {
                        completion?(nil)
                        return
                    }

                    let batch = self.db.batch()
                    docs.forEach { batch.deleteDocument($0.reference) }
                    batch.commit { batchError in
                        completion?(batchError)
                    }
                }
        }
    }

    func updateProfile(for uid: String,
                       displayName: String,
                       handle: String,
                       bio: String?,
                       completion: ((Error?) -> Void)? = nil) {
        let normalizedHandle = HandleFormatter.normalizedHandle(from: handle)
        let sanitizedHandle: String
        if normalizedHandle.hasPrefix("@") {
            sanitizedHandle = String(normalizedHandle.dropFirst())
        } else {
            sanitizedHandle = normalizedHandle
        }
        let updates: [String: Any?] = [
            "displayName": displayName,
            "handle": sanitizedHandle,
            "bio": bio
        ]

        let filtered = updates.compactMapValues { $0 }
        db.collection("users").document(uid).updateData(filtered) { error in
            completion?(error)
        }
    }

    func updatePhoneNumber(for uid: String,
                           phoneNumber: String,
                           completion: ((Error?) -> Void)? = nil) {
        db.collection("users")
            .document(uid)
            .updateData(["phoneNumber": phoneNumber]) { error in
                completion?(error)
            }
    }

    func updateNotificationSettings(for uid: String,
                                    settings: AppUser.NotificationSettings,
                                    completion: ((Error?) -> Void)? = nil) {
        do {
            let data = try Firestore.Encoder().encode(settings)
            db.collection("users")
                .document(uid)
                .setData(["notificationSettings": data], merge: true) { error in
                    completion?(error)
                }
        } catch {
            completion?(error)
        }
    }

    func updatePrivacySettings(for uid: String,
                               settings: AppUser.PrivacySettings,
                               completion: ((Error?) -> Void)? = nil) {
        do {
            let data = try Firestore.Encoder().encode(settings)
            db.collection("users")
                .document(uid)
                .setData(["privacySettings": data], merge: true) { error in
                    completion?(error)
                }
        } catch {
            completion?(error)
        }
    }

    func backfillHandles(completion: ((Error?) -> Void)? = nil) {
        db.collection("users").getDocuments { snapshot, error in
            if let error = error {
                completion?(error)
                return
            }

            guard let documents = snapshot?.documents else {
                completion?(nil)
                return
            }

            let batch = self.db.batch()
            for document in documents {
                guard let user = try? document.data(as: AppUser.self) else { continue }
                let trimmed = user.handle.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    let fallback = HandleFormatter.normalizedHandle(from: user.displayName)
                    let sanitized = String(fallback.dropFirst())
                    batch.updateData(["handle": sanitized], forDocument: document.reference)
                }
            }

            batch.commit { error in
                completion?(error)
            }
        }
    }

    func fetchContactSuggestions(for uid: String, limit: Int = 8, completion: @escaping ([AppUser]) -> Void) {
        db.collection("users")
            .whereField("privacySettings.allowContactDiscovery", isEqualTo: true)
            .limit(to: limit)
            .getDocuments { snapshot, _ in
                let users = snapshot?.documents.compactMap { try? $0.data(as: AppUser.self) } ?? []
                let filtered = users.filter { $0.id != uid }
                completion(filtered)
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
