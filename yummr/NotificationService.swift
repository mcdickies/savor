import Foundation
import FirebaseFirestore
import FirebaseAuth

struct AppNotification: Identifiable, Codable {
    enum Kind: String, Codable {
        case like
        case comment
        case friendRequest
    }

    @DocumentID var id: String?
    var type: Kind
    var actorID: String
    var message: String
    var postID: String?
    @ServerTimestamp var createdAt: Date?
    var isRead: Bool?
}

final class NotificationService: ObservableObject {
    static let shared = NotificationService()
    private let db = Firestore.firestore()

    private init() {}

    func observeNotifications(for uid: String, listener: @escaping ([AppNotification]) -> Void) -> ListenerRegistration {
        db.collection("users")
            .document(uid)
            .collection("notifications")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                let notifications = snapshot?.documents.compactMap { try? $0.data(as: AppNotification.self) } ?? []
                listener(notifications)
            }
    }

    func markNotificationRead(uid: String, notificationID: String) {
        db.collection("users")
            .document(uid)
            .collection("notifications")
            .document(notificationID)
            .updateData(["isRead": true])
    }

    func markAllRead(uid: String) {
        db.collection("users")
            .document(uid)
            .collection("notifications")
            .whereField("isRead", isEqualTo: false)
            .getDocuments { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let batch = self.db.batch()
                docs.forEach { batch.updateData(["isRead": true], forDocument: $0.reference) }
                batch.commit()
            }
    }

    func createNotification(
        to recipientID: String,
        type: AppNotification.Kind,
        actorID: String,
        message: String,
        postID: String? = nil
    ) {
        guard recipientID != actorID else { return }

        UserService.shared.fetchUser(withID: recipientID) { user in
            let settings = user?.resolvedNotificationSettings ?? .default
            if settings.mutedUserIDs?.contains(actorID) == true {
                return
            }

            switch type {
            case .like where settings.likes == false:
                return
            case .comment where settings.comments == false:
                return
            case .friendRequest where settings.friendRequests == false:
                return
            default:
                break
            }

            let notification = AppNotification(
                type: type,
                actorID: actorID,
                message: message,
                postID: postID,
                createdAt: Date(),
                isRead: false
            )

            do {
                _ = try self.db.collection("users")
                    .document(recipientID)
                    .collection("notifications")
                    .addDocument(from: notification)
            } catch {
                print("Failed to create notification: \(error)")
            }
        }
    }
}
