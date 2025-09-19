import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import FirebaseFirestore 
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

        let authorName = Auth.auth().currentUser?.displayName
                      ?? Auth.auth().currentUser?.email
                      ?? "Unknown"

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
