import SwiftUI
import FirebaseFirestore

struct NotificationsView: View {
    @EnvironmentObject var auth: AuthService
    @State private var notifications: [AppNotification] = []
    @State private var listener: ListenerRegistration?
    @State private var selectedPost: Post?

    private let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                if notifications.isEmpty {
                    Text("You're all caught up!")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(notifications) { notification in
                        notificationRow(notification)
                    }
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Mark all read") {
                        markAllRead()
                    }
                    .disabled(notifications.allSatisfy { $0.isRead == true })
                }
            }
            .onAppear(perform: startListening)
            .onDisappear(perform: stopListening)
            .sheet(item: $selectedPost) { post in
                NavigationStack {
                    PostDetailView(post: post)
                        .environmentObject(auth)
                }
            }
        }
    }

    private func notificationRow(_ notification: AppNotification) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(notification.message)
                    .font(.body)
                Spacer()
                if notification.isRead == false {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                }
            }

            HStack(spacing: 12) {
                if let createdAt = notification.createdAt {
                    Text(formatter.localizedString(for: createdAt, relativeTo: Date()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if notification.type == .friendRequest {
                    Button("Accept") {
                        acceptFriendRequest(notification)
                    }
                    .font(.caption)
                    Button("Dismiss") {
                        markRead(notification)
                    }
                    .font(.caption)
                } else if notification.postID != nil {
                    Button("Open") {
                        openPost(notification)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 6)
        .onTapGesture {
            markRead(notification)
        }
    }

    private func startListening() {
        guard let uid = auth.currentUser?.uid else { return }
        listener?.remove()
        listener = NotificationService.shared.observeNotifications(for: uid) { notifications in
            DispatchQueue.main.async {
                self.notifications = notifications
            }
        }
    }

    private func stopListening() {
        listener?.remove()
        listener = nil
    }

    private func markAllRead() {
        guard let uid = auth.currentUser?.uid else { return }
        NotificationService.shared.markAllRead(uid: uid)
    }

    private func markRead(_ notification: AppNotification) {
        guard let uid = auth.currentUser?.uid, let id = notification.id else { return }
        NotificationService.shared.markNotificationRead(uid: uid, notificationID: id)
    }

    private func acceptFriendRequest(_ notification: AppNotification) {
        FriendService.shared.acceptFriendRequest(from: notification.actorID)
        markRead(notification)
    }

    private func openPost(_ notification: AppNotification) {
        guard let postID = notification.postID else { return }
        Firestore.firestore()
            .collection("posts")
            .document(postID)
            .getDocument { snapshot, _ in
                guard let snapshot, let post = try? snapshot.data(as: Post.self) else { return }
                DispatchQueue.main.async {
                    selectedPost = post
                }
            }
        markRead(notification)
    }
}
