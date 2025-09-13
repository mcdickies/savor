
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
        image: UIImage,
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

        let imageID = UUID().uuidString
        let imageRef = storage.reference().child("images/\(imageID).jpg")

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(
                NSError(domain: "ImageError", code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Could not convert image."])
            ))
            return
        }

        imageRef.putData(imageData, metadata: nil) { _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            imageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let downloadURL = url else {
                    completion(.failure(
                        NSError(domain: "StorageError", code: 0,
                                userInfo: [NSLocalizedDescriptionKey: "Could not get download URL."])
                    ))
                    return
                }

                // Store URLs in both the new array-based field and the legacy
                // single URL field so older app versions can still read posts.
                let downloadURLs = [downloadURL.absoluteString]
                let postData: [String: Any] = [
                    "title": title,
                    "description": description,
                    "imageURL": downloadURLs.first ?? "",
                    "imageURLs": downloadURLs,
                    "timestamp": Date(),
                    "authorID": uid,
                    "authorName": authorName,
                    "likedBy": [],
                    "likeCount": 0
                ]

                self.db.collection("posts").addDocument(data: postData) { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        }
    }
}
