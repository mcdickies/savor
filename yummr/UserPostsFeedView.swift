import SwiftUI
import FirebaseFirestore

struct UserPostsFeedView: View {
    let authorID: String
    var authorName: String?

    @State private var posts: [Post] = []
    @State private var isLoading = true

    private let db = Firestore.firestore()

    private var navigationTitle: String {
        if let name = authorName, !name.isEmpty {
            if name.lowercased().hasSuffix("s") {
                return "\(name)' Posts"
            } else {
                return "\(name)'s Posts"
            }
        } else {
            return "User Posts"
        }
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading posts...")
                    .padding()
            } else if posts.isEmpty {
                Text("No posts to show yet.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVStack(spacing: 24) {
                    ForEach(posts) { post in
                        PostCard(post: post)
                    }
                }
                .padding(.vertical)
            }
        }
        .padding(.horizontal)
        .navigationTitle(navigationTitle)
        .onAppear {
            fetchPosts()
        }
    }

    private func fetchPosts() {
        isLoading = true

        db.collection("posts")
            .whereField("authorID", isEqualTo: authorID)
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                self.isLoading = false

                if let error = error {
                    print("Failed to fetch user posts: \(error)")
                    self.posts = []
                    return
                }

                guard let documents = snapshot?.documents else {
                    self.posts = []
                    return
                }

                self.posts = documents.compactMap { try? $0.data(as: Post.self) }
            }
    }
}
