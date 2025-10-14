import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift
import FirebaseStorage
import FirebaseAuth
import UIKit
import Combine

class PostService: ObservableObject {

    static let shared = PostService()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    @Published var cachedTopPosts: [Post] = []

    func toggleLike(for post: Post, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let postID = post.id else {
            completion(.failure(
                NSError(domain: "PostError", code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Post ID is missing."])
            ))
            return
        }
        let postRef = db.collection("posts").document(postID)

        db.runTransaction({ transaction, errorPointer in
            let postDoc: DocumentSnapshot
            do {
                try postDoc = transaction.getDocument(postRef)
            } catch let error {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard var likedBy = postDoc.data()?["likedBy"] as? [String],
                  var likeCount = postDoc.data()?["likeCount"] as? Int else {
                return nil
            }

            if likedBy.contains(uid) {
                likedBy.removeAll { $0 == uid }
                likeCount -= 1
            } else {
                likedBy.append(uid)
                likeCount += 1
            }

            transaction.updateData([
                "likedBy": likedBy,
                "likeCount": likeCount
            ], forDocument: postRef)

            return nil
        }) { _, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func uploadPost(
        title: String,
        description: String,
        recipe: String?,
        cookTime: String?,
        taggedUserIDs: [String],
        photoTags: [Post.PhotoTag],
        extraFields: [String: String] = [:],
        images: [UIImage],
        detailImages: [UIImage] = [],
        progressHandler: ((Int, Double) -> Void)? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(
                NSError(domain: "AuthError", code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "User not logged in."])
            ))
            return
        }

        resolveAuthorName(for: uid) { authorName in
            var urls: [String] = Array(repeating: "", count: images.count)
            var detailURLs: [String] = Array(repeating: "", count: detailImages.count)
            var uploadError: Error?
            let group = DispatchGroup()

            for (index, image) in images.enumerated() {
                group.enter()

                guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                    uploadError = NSError(domain: "ImageError", code: 0,
                                          userInfo: [NSLocalizedDescriptionKey: "Could not convert image."])
                    group.leave()
                    continue
                }

                let imageID = UUID().uuidString
                let imageRef = storage.reference().child("images/\(imageID).jpg")
                let uploadTask = imageRef.putData(imageData, metadata: nil)

                uploadTask.observe(.progress) { snapshot in
                    let progress = Double(snapshot.progress?.completedUnitCount ?? 0) /
                                    Double(snapshot.progress?.totalUnitCount ?? 1)
                    progressHandler?(index, progress)
                }

                uploadTask.observe(.success) { _ in
                    imageRef.downloadURL { url, error in
                        if let error = error {
                            uploadError = error
                        } else if let url = url {
                            urls[index] = url.absoluteString
                            progressHandler?(index, 1.0)
                        }
                        group.leave()
                    }
                }

                uploadTask.observe(.failure) { snapshot in
                    if let error = snapshot.error {
                        uploadError = error
                    }
                    group.leave()
                }
            }

            for (index, image) in detailImages.enumerated() {
                group.enter()
                guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                    uploadError = NSError(domain: "ImageError", code: 0,
                                          userInfo: [NSLocalizedDescriptionKey: "Could not convert detail image."])
                    group.leave()
                    continue
                }

                let imageID = UUID().uuidString
                let imageRef = storage.reference().child("images/detail/\(imageID).jpg")
                imageRef.putData(imageData, metadata: nil) { _, error in
                    if let error = error {
                        uploadError = error
                        group.leave()
                        return
                    }
                    imageRef.downloadURL { url, error in
                        if let error = error {
                            uploadError = error
                        } else if let url = url {
                            detailURLs[index] = url.absoluteString
                        }
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                if let error = uploadError {
                    completion(.failure(error))
                    return
                }

                let uniqueTagged = Array(Set(taggedUserIDs))
                let sanitizedExtras = extraFields.isEmpty ? nil : extraFields
                let sanitizedDetailURLs = detailURLs.isEmpty ? nil : detailURLs

                let post = Post(
                    title: title,
                    description: description,
                    recipe: recipe,
                    cookTime: cookTime,
                    imageURLs: urls,
                    detailImages: sanitizedDetailURLs,
                    extraFields: sanitizedExtras,
                    timestamp: Date(),
                    authorID: uid,
                    authorName: authorName,
                    likedBy: [],
                    likeCount: 0,
                    taggedUserIDs: uniqueTagged,
                    photoTags: photoTags
                )

                do {
                    _ = try self.db.collection("posts").addDocument(from: post)
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private func resolveAuthorName(for uid: String, completion: @escaping (String) -> Void) {
        db.collection("users").document(uid).getDocument { snapshot, _ in
            if let appUser = try? snapshot?.data(as: AppUser.self) {
                let trimmedHandle = appUser.handle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedHandle.isEmpty {
                    completion(HandleFormatter.normalizedHandle(from: trimmedHandle))
                    return
                }

                let displayName = appUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !displayName.isEmpty {
                    completion(HandleFormatter.normalizedHandle(from: displayName))
                    return
                }
            }

            let fallback = Auth.auth().currentUser?.displayName
                        ?? Auth.auth().currentUser?.email
                        ?? "Unknown"
            completion(HandleFormatter.normalizedHandle(from: fallback))
        }
    }

    func preloadTopPosts(limit: Int = 5, completion: (() -> Void)? = nil) {
        db.collection("posts")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments { snapshot, _ in
                let posts = snapshot?.documents.compactMap { try? $0.data(as: Post.self) } ?? []
                DispatchQueue.main.async {
                    self.cachedTopPosts = posts
                    completion?()
                }
            }
    }

    func updatePost(postID: String,
                    title: String? = nil,
                    description: String,
                    recipeSteps: [String],
                    extraFields: [String: String],
                    completion: @escaping (Result<Void, Error>) -> Void) {
        var sanitizedExtras = extraFields
        let sanitizedIngredients = sanitizeIngredients(extraFields["ingredients"])
        if !sanitizedIngredients.isEmpty {
            sanitizedExtras["ingredients"] = sanitizedIngredients.joined(separator: ", ")
        }

        let sanitizedRecipe = sanitizeInstructions(recipeSteps)
        let recipeString = sanitizedRecipe.joined(separator: "\n")

        var payload: [String: Any] = [
            "description": description,
            "recipe": recipeString
        ]

        if let title = title {
            payload["title"] = title
        }

        payload["extraFields"] = sanitizedExtras

        db.collection("posts").document(postID).updateData(payload) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func searchPosts(matching query: String, limit: Int = 20, completion: @escaping ([Post]) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion([])
            return
        }

        db.collection("posts")
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .getDocuments { snapshot, _ in
                let posts = snapshot?.documents.compactMap { try? $0.data(as: Post.self) } ?? []
                let lower = trimmed.lowercased()
                let filtered = posts.filter { post in
                    let titleMatch = post.title.lowercased().contains(lower)
                    let descriptionMatch = post.description.lowercased().contains(lower)
                    let recipeMatch = (post.recipe ?? "").lowercased().contains(lower)
                    let cookTimeMatch = (post.cookTime ?? "").lowercased().contains(lower)
                    let ingredientMatch = post.extraFields?.values.contains(where: { $0.lowercased().contains(lower) }) ?? false
                    return titleMatch || descriptionMatch || recipeMatch || cookTimeMatch || ingredientMatch
                }
                completion(Array(filtered.prefix(limit)))
            }
    }

    func fetchTaggedPosts(for userID: String, completion: @escaping ([Post]) -> Void) {
        db.collection("posts")
            .whereField("taggedUserIDs", arrayContains: userID)
            .getDocuments { snapshot, _ in
                let posts = snapshot?.documents.compactMap { try? $0.data(as: Post.self) } ?? []
                completion(posts)
            }
    }
}

private extension PostService {
    func sanitizeIngredients(_ rawValue: String?) -> [String] {
        guard let rawValue = rawValue else { return [] }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var items: [String] = []
        var current = ""
        var depth = 0

        for character in trimmed { 
            switch character {
            case "(":
                depth += 1
                current.append(character)
            case ")":
                depth = max(0, depth - 1)
                current.append(character)
            case ",", "\n", "•":
                if depth == 0 {
                    let candidate = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty {
                        items.append(candidate)
                    }
                    current = ""
                } else {
                    current.append(character)
                }
            default:
                current.append(character)
            }
        }

        let final = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !final.isEmpty { items.append(final) }
        return items
    }

    func sanitizeInstructions(_ steps: [String]) -> [String] {
        steps.map { step in
            let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            let components = trimmed.components(separatedBy: CharacterSet(charactersIn: ".-)"))
            let cleanedStart = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let first = cleanedStart.split(separator: " ").first, first.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil {
                let remainder = trimmed.dropFirst(first.count)
                let sanitizedRemainder = remainder.trimmingCharacters(in: CharacterSet(charactersIn: ".- )"))
                return sanitizedRemainder
            }
            return trimmed
        }.filter { !$0.isEmpty }
    }
}
