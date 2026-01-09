import Foundation
import FirebaseAuth
import FirebaseFirestore

final class CommentService {
    static let shared = CommentService()
    private let db = Firestore.firestore()

    private init() {}

    func toggleLike(postID: String,
                    commentID: String,
                    parentCommentID: String?,
                    completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(
                domain: "AuthError",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "User not logged in."]
            )))
            return
        }

        let commentRef = commentReference(postID: postID, commentID: commentID, parentCommentID: parentCommentID)

        db.runTransaction({ transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(commentRef)
            } catch let error {
                errorPointer?.pointee = error as NSError
                return nil
            }

            var likedBy = snapshot.data()?["likedBy"] as? [String] ?? []
            var likeCount = snapshot.data()?["likeCount"] as? Int ?? likedBy.count

            if likedBy.contains(uid) {
                likedBy.removeAll { $0 == uid }
                likeCount = max(0, likeCount - 1)
            } else {
                likedBy.append(uid)
                likeCount += 1
            }

            transaction.updateData([
                "likedBy": likedBy,
                "likeCount": likeCount
            ], forDocument: commentRef)

            return nil
        }) { _, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    private func commentReference(postID: String, commentID: String, parentCommentID: String?) -> DocumentReference {
        if let parentID = parentCommentID, !parentID.isEmpty {
            return db.collection("posts")
                .document(postID)
                .collection("comments")
                .document(parentID)
                .collection("replies")
                .document(commentID)
        }

        return db.collection("posts")
            .document(postID)
            .collection("comments")
            .document(commentID)
    }
}
