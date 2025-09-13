import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
//push

struct PostCard: View {
    var post: Post
    @State private var likeCount: Int
    @State private var isLiked: Bool
    @State private var isProcessingLike = false
    @State private var previewComments: [Comment] = []
    @State private var showAllComments = false
    @State private var commentCount = 0

    init(post: Post) {
        self.post = post
        _likeCount = State(initialValue: post.likeCount)
        _isLiked = State(initialValue: post.likedBy.contains(Auth.auth().currentUser?.uid ?? ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.title)
                .font(.headline)

            Text("By \(post.authorName)")
                .font(.subheadline)
                .foregroundColor(.gray)

            AsyncImage(url: URL(string: post.imageURL)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)
                case .failure:
                    Image(systemName: "photo")
                @unknown default:
                    EmptyView()
                }
            }

            Text(post.description)
                .font(.body)

            HStack(spacing: 10) {
                Button(action: toggleLike) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundColor(isLiked ? .red : .gray)
                }
                Text("\(likeCount)")
                    .foregroundColor(.gray)
                    .font(.subheadline)
            }
            .padding(.top, 4)

            // 💬 Preview Comments
            VStack(alignment: .leading, spacing: 6) {
                ForEach(previewComments.prefix(2)) { comment in
                    HStack(alignment: .top, spacing: 6) {
                        Text(comment.authorName)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(comment.text)
                            .font(.caption)
                    }
                }

                if commentCount > 2 {
                    Button("View all comments") {
                        showAllComments = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
        .onAppear {
            fetchPreviewComments()
        }
        .sheet(isPresented: $showAllComments, onDismiss: {
            // refresh preview after closing full list
            fetchPreviewComments()
        }) {
            AllCommentsView(post: post)
        }
    }

    private func toggleLike() {
        guard !isProcessingLike else { return }
        isProcessingLike = true

        PostService.shared.toggleLike(for: post) { result in
            DispatchQueue.main.async {
                switch result {
                case .success():
                    isLiked.toggle()
                    likeCount += isLiked ? 1 : -1
                case .failure(let error):
                    print("Failed to like post: \(error)")
                }
                isProcessingLike = false
            }
        }
    }

    private func fetchPreviewComments() {
        guard let postID = post.id else { return }
        Firestore.firestore()
            .collection("posts")
            .document(postID)
            .collection("comments")
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Preview comments fetch error:", error)
                    return
                }
                guard let docs = snapshot?.documents else { return }
                do {
                    let allComments: [Comment] = try docs.map { try $0.data(as: Comment.self) }
                    self.commentCount = allComments.count
                    self.previewComments = Array(allComments.prefix(2))
                } catch {
                    print("Preview comments decode error:", error)
                }
            }
    }
}
