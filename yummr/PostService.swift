
import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import UIKit
import Combine
//push
class PostService: ObservableObject {

    static let shared = PostService()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

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
        images: [UIImage],
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

        // Use displayName if set, else fallback to email
        let authorName = Auth.auth().currentUser?.displayName
                      ?? Auth.auth().currentUser?.email
                      ?? "Unknown"

        var urls: [String] = Array(repeating: "", count: images.count)
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

        group.notify(queue: .main) {
            if let error = uploadError {
                completion(.failure(error))
                return
            }

            let post = Post(
                title: title,
                description: description,
                imageURLs: urls,
                timestamp: Date(),
                authorID: uid,
                authorName: authorName,
                likedBy: [],
                likeCount: 0
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
