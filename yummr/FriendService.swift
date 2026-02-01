import Foundation
import FirebaseFirestore
import FirebaseAuth

final class FriendService: ObservableObject {
    static let shared = FriendService()
    private let db = Firestore.firestore()

    private init() {}

    func observeFriendIDs(for uid: String, listener: @escaping ([String]) -> Void) -> ListenerRegistration {
        db.collection("users")
            .document(uid)
            .collection("friends")
            .addSnapshotListener { snapshot, _ in
                let ids = snapshot?.documents.compactMap { $0.documentID } ?? []
                listener(ids)
            }
    }

    func fetchFriendIDs(for uid: String, completion: @escaping (Result<[String], Error>) -> Void) {
        db.collection("users")
            .document(uid)
            .collection("friends")
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                let ids = snapshot?.documents.compactMap { $0.documentID } ?? []
                completion(.success(ids))
            }
    }

    func observeIncomingRequests(for uid: String, listener: @escaping ([String]) -> Void) -> ListenerRegistration {
        db.collection("users")
            .document(uid)
            .collection("friendRequests")
            .addSnapshotListener { snapshot, _ in
                let ids = snapshot?.documents.compactMap { $0.documentID } ?? []
                listener(ids)
            }
    }

    func sendFriendRequest(to targetUID: String, completion: ((Error?) -> Void)? = nil) {
        guard let currentUID = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        let request = [
            "from": currentUID,
            "createdAt": FieldValue.serverTimestamp()
        ] as [String: Any]

        db.collection("users")
            .document(targetUID)
            .collection("friendRequests")
            .document(currentUID)
            .setData(request, merge: true, completion: completion)
    }

    func cancelFriendRequest(to targetUID: String, completion: ((Error?) -> Void)? = nil) {
        guard let currentUID = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }
        db.collection("users")
            .document(targetUID)
            .collection("friendRequests")
            .document(currentUID)
            .delete(completion: completion)
    }

    func acceptFriendRequest(from requesterUID: String, completion: ((Error?) -> Void)? = nil) {
        guard let currentUID = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        let friendData = [
            "createdAt": FieldValue.serverTimestamp()
        ]

        let batch = db.batch()
        let currentFriendRef = db.collection("users").document(currentUID)
            .collection("friends").document(requesterUID)
        let requesterFriendRef = db.collection("users").document(requesterUID)
            .collection("friends").document(currentUID)
        batch.setData(friendData, forDocument: currentFriendRef)
        batch.setData(friendData, forDocument: requesterFriendRef)

        let requestRef = db.collection("users")
            .document(currentUID)
            .collection("friendRequests")
            .document(requesterUID)
        batch.deleteDocument(requestRef)

        batch.commit { error in
            if error == nil {
                self.incrementFriendCounts(for: [currentUID, requesterUID], delta: 1)
            }
            completion?(error)
        }
    }

    func removeFriend(_ friendUID: String, completion: ((Error?) -> Void)? = nil) {
        guard let currentUID = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        let batch = db.batch()
        let currentRef = db.collection("users").document(currentUID)
            .collection("friends").document(friendUID)
        let otherRef = db.collection("users").document(friendUID)
            .collection("friends").document(currentUID)
        batch.deleteDocument(currentRef)
        batch.deleteDocument(otherRef)
        batch.commit { error in
            if error == nil {
                self.incrementFriendCounts(for: [currentUID, friendUID], delta: -1)
            }
            completion?(error)
        }
    }

    func createFriendship(with targetUID: String, completion: ((Error?) -> Void)? = nil) {
        guard let currentUID = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        guard currentUID != targetUID else {
            completion?(nil)
            return
        }

        let friendData = [
            "createdAt": FieldValue.serverTimestamp()
        ]

        let batch = db.batch()
        let currentFriendRef = db.collection("users").document(currentUID)
            .collection("friends").document(targetUID)
        let targetFriendRef = db.collection("users").document(targetUID)
            .collection("friends").document(currentUID)

        batch.setData(friendData, forDocument: currentFriendRef, merge: true)
        batch.setData(friendData, forDocument: targetFriendRef, merge: true)

        batch.commit { error in
            if error == nil {
                self.incrementFriendCounts(for: [currentUID, targetUID], delta: 1)
                UserService.shared.fetchUser(withID: currentUID) { user in
                    let actorName = HandleFormatter.normalizedHandleIfPresent(user?.handle)
                        ?? HandleFormatter.normalizedHandle(from: user?.displayName ?? "Someone")
                    let message = "\(actorName) followed you"
                    NotificationService.shared.createNotification(
                        to: targetUID,
                        type: .friendRequest,
                        actorID: currentUID,
                        message: message
                    )
                }
            }
            completion?(error)
        }
    }

    func isFriends(with targetUID: String, completion: @escaping (Bool) -> Void) {
        guard let currentUID = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }

        db.collection("users")
            .document(currentUID)
            .collection("friends")
            .document(targetUID)
            .getDocument { snapshot, _ in
                completion(snapshot?.exists ?? false)
            }
    }

    func hasPendingRequest(to targetUID: String, completion: @escaping (Bool) -> Void) {
        guard let currentUID = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }

        db.collection("users")
            .document(targetUID)
            .collection("friendRequests")
            .document(currentUID)
            .getDocument { snapshot, _ in
                completion(snapshot?.exists ?? false)
            }
    }

    private func incrementFriendCounts(for uids: [String], delta: Int64) {
        guard delta != 0 else { return }
        let batch = db.batch()
        uids.forEach { uid in
            let userRef = db.collection("users").document(uid)
            batch.setData([
                "followerCount": FieldValue.increment(delta),
                "followingCount": FieldValue.increment(delta)
            ], forDocument: userRef, merge: true)
        }
        batch.commit(completion: nil)
    }
}
