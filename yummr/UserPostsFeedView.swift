import SwiftUI
import FirebaseFirestore
import FirebaseFirestore

struct UserPostsFeedView: View {
    let authorID: String
    var authorName: String?
    var initialPostID: String? = nil
    var sourcePosts: [Post]? = nil

    @State private var posts: [Post] = []
    @State private var isLoading = true
    @State private var listener: ListenerRegistration?
    @State private var hasScrolledToInitialPost = false

    private let db = Firestore.firestore()

    var body: some View {
        ScrollViewReader { proxy in
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
                            let identifier = post.stableIdentifier
                            NavigationLink(destination: PostDetailView(post: post)) {
                                PostCard(post: post)
                            }
                            .buttonStyle(.plain)
                            .id(identifier)
                        }
                    }
                    .padding()
                }
            }
        .onChange(of: posts.map { $0.stableIdentifier }) { _ in
            guard !hasScrolledToInitialPost,
                  let targetID = initialPostID,
                  posts.contains(where: { $0.stableIdentifier == targetID }) else { return }
            withAnimation {
                proxy.scrollTo(targetID, anchor: .top)
            }
            hasScrolledToInitialPost = true
        }
        }
        .navigationTitle(title)
        .onAppear {
            hasScrolledToInitialPost = false
            if let sourcePosts {
                posts = sourcePosts
                isLoading = false
            } else {
                startListeningForPosts()
            }
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
