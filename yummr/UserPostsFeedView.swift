import SwiftUI
import FirebaseFirestore
import FirebaseFirestoreSwift

struct UserPostsFeedView: View {
    let authorID: String
    var authorName: String?

    @State private var posts: [Post] = []
    @State private var isLoading = true
    @State private var listener: ListenerRegistration?

    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding()
            } else if posts.isEmpty {
                Text("No posts yet.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVStack(spacing: 24) {
                    ForEach(posts) { post in
                        PostCard(post: post)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(title)
        .onAppear {
            startListeningForPosts()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    private var title: String {
        if let name = authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return "\(name)'s Posts"
        } else {
            return "User Posts"
        }
    }

    private func startListeningForPosts() {
        listener?.remove()
        isLoading = true

        listener = db.collection("posts")
            .whereField("authorID", isEqualTo: authorID)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error fetching user posts:", error)
                        self.posts = []
                        self.isLoading = false
                        return
                    }

                    guard let documents = snapshot?.documents else {
                        self.posts = []
                        self.isLoading = false
                        return
                    }

                    self.posts = documents.compactMap { try? $0.data(as: Post.self) }
                    self.isLoading = false
                }
            }
    }
}
