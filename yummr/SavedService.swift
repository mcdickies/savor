import Foundation
import FirebaseFirestore
import FirebaseAuth

final class SavedService: ObservableObject {
    static let shared = SavedService()
    private let db = Firestore.firestore()

    private init() {}

    func observeCollections(for uid: String, listener: @escaping ([AppUser.SavedCollection]) -> Void) -> ListenerRegistration {
        db.collection("users")
            .document(uid)
            .collection("collections")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, _ in
                let collections = snapshot?.documents.compactMap { try? $0.data(as: AppUser.SavedCollection.self) } ?? []
                if collections.isEmpty {
                    self.ensureDefaultCollection(for: uid)
                    listener([AppUser.SavedCollection(id: "all", title: "All Saves")])
                } else {
                    listener(collections)
                }
            }
    }

    func ensureDefaultCollection(for uid: String) {
        db.collection("users")
            .document(uid)
            .collection("collections")
            .document("all")
            .setData([
                "title": "All Saves",
                "postIDs": [],
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    func createCollection(uid: String, title: String, completion: ((Error?) -> Void)? = nil) {
        let data: [String: Any] = [
            "title": title,
            "postIDs": [],
            "createdAt": FieldValue.serverTimestamp()
        ]
        db.collection("users")
            .document(uid)
            .collection("collections")
            .addDocument(data: data, completion: completion)
    }

    func toggleSave(post: Post, collectionID: String = "all", completion: ((Result<Bool, Error>) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid, let postID = post.id else { return }
        ensureDefaultCollection(for: uid)
        let collectionRef = db.collection("users")
            .document(uid)
            .collection("collections")
            .document(collectionID)

        collectionRef.getDocument { snapshot, error in
            if let error = error {
                completion?(.failure(error))
                return
            }

            let existing = (try? snapshot?.data(as: AppUser.SavedCollection.self)) ?? AppUser.SavedCollection(id: collectionID, title: collectionID == "all" ? "All Saves" : collectionID)
            var postIDs = existing.postIDs
            let isSaved: Bool
            if postIDs.contains(postID) {
                postIDs.removeAll { $0 == postID }
                isSaved = false
            } else {
                postIDs.append(postID)
                isSaved = true
            }

            var payload: [String: Any] = [
                "title": existing.title,
                "postIDs": postIDs
            ]
            if existing.createdAt == nil {
                payload["createdAt"] = FieldValue.serverTimestamp()
            }

            collectionRef.setData(payload, merge: true) { error in
                if let error = error {
                    completion?(.failure(error))
                } else {
                    completion?(.success(isSaved))
                }
            }
        }
    }

    func isPostSaved(postID: String, completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        db.collection("users")
            .document(uid)
            .collection("collections")
            .document("all")
            .getDocument { snapshot, _ in
                let collection = try? snapshot?.data(as: AppUser.SavedCollection.self)
                let saved = collection?.postIDs.contains(postID) ?? false
                completion(saved)
            }
    }
}
