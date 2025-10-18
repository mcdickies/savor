import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFirestoreSwift

struct PostCard: View {
    var post: Post
    @State private var likeCount: Int
    @State private var isLiked: Bool
    @State private var isProcessingLike = false
    @State private var showAllComments = false
    @State private var commentCount = 0
    @State private var showTagsOverlay = false
    @State private var currentImageIndex = 0
    @State private var taggedUsers: [String: AppUser] = [:]
    @State private var previewComments: [Comment] = []
    @State private var isSaved = false

    init(post: Post) {
        self.post = post
        _likeCount = State(initialValue: post.likeCount)
        _isLiked = State(initialValue: post.likedBy.contains(Auth.auth().currentUser?.uid ?? ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let caption = captionText {
                Text(caption)
                    .appTextStyle(.body)
                    .foregroundColor(.primary)
            }

            tabbedImages

            if !post.photoTags.isEmpty {
                Button {
                    withAnimation(.easeInOut) {
                        showTagsOverlay.toggle()
                    }
                } label: {
                    Label(showTagsOverlay ? "Hide tags" : "Show tags", systemImage: showTagsOverlay ? "tag.fill" : "tag")
                        .appTextStyle(.caption, weight: .medium)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

            interactionBar

            if !previewComments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(previewComments.sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(HandleFormatter.normalizedHandle(from: comment.authorName))
                                .appTextStyle(.caption, weight: .semibold)
                                .foregroundColor(.secondary)
                            Text(comment.text)
                                .appTextStyle(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                        }
                    }

                    Button("View more comments") {
                        showAllComments = true
                    }
                    .appTextStyle(.caption, weight: .semibold)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(16)
        .onAppear {
            fetchCommentsPreview()
            fetchTaggedUsers()
            checkSaveState()
        }
        .sheet(isPresented: $showAllComments, onDismiss: {
            fetchCommentsPreview()
        }) {
            AllCommentsView(post: post)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(post.title)
                    .appTextStyle(.title3, weight: .semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()

                if let rating = post.starRating {
                    StarRatingView(rating: rating)
                }

                if post.isFavorited {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                        .accessibilityLabel("Favorited")
                }
            }

            NavigationLink(destination: ProfileView(userID: post.authorID)) {
                Text("by \(HandleFormatter.normalizedHandle(from: post.authorName))")
                    .appTextStyle(.caption)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private var interactionBar: some View {
        HStack(spacing: 16) {
            Button(action: toggleLike) {
                HStack(spacing: 6) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundColor(isLiked ? .red : .secondary)
                    Text("\(likeCount)")
                        .appTextStyle(.subheadline, weight: .medium)
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: toggleSave) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .foregroundColor(isSaved ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                showAllComments = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .foregroundColor(.secondary)
                    Text(commentCount == 0 ? "Comment" : "\(commentCount) comments")
                        .appTextStyle(.subheadline, weight: .medium)
                        .foregroundColor(.accentColor)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private func toggleSave() {
        SavedService.shared.toggleSave(post: post) { result in
            DispatchQueue.main.async {
                if case .success(let saved) = result {
                    self.isSaved = saved
                }
            }
        }
    }

    private func checkSaveState() {
        guard let postID = post.id else { return }
        SavedService.shared.isPostSaved(postID: postID) { saved in
            DispatchQueue.main.async {
                self.isSaved = saved
            }
        }
    }

    private var captionText: String? {
        let trimmed = post.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var tabbedImages: some View {
        TabView(selection: $currentImageIndex) {
            ForEach(Array(post.imageURLs.enumerated()), id: \.offset) { item in
                GeometryReader { geometry in
                    ZStack {
                        CachedWebImage(url: URL(string: item.element)) {
                            ProgressView()
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()

                        if showTagsOverlay {
                            ForEach(tags(for: item.offset), id: \.id) { tag in
                                tagOverlay(tag: tag, geometry: geometry)
                            }
                        }
                    }
                }
                .frame(height: 300)
                .cornerRadius(16)
                .padding(.bottom, 4)
                .tag(item.offset)
            }
        }
        .frame(height: 300)
        .tabViewStyle(PageTabViewStyle())
    }

    private func tagOverlay(tag: Post.PhotoTag, geometry: GeometryProxy) -> some View {
        let size = geometry.size
        let position = position(for: tag, in: size)
        let label = tagLabel(for: tag)
        return Group {
            if let position = position {
                Text(label)
                    .appTextStyle(.caption2, weight: .semibold)
                    .padding(6)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .position(position)
            }
        }
    }

    private func tags(for index: Int) -> [Post.PhotoTag] {
        post.photoTags.filter { tag in
            guard let imageIndex = tag.imageIndex else { return false }
            return imageIndex == index
        }
    }

    private func position(for tag: Post.PhotoTag, in size: CGSize) -> CGPoint? {
        guard let x = tag.x, let y = tag.y else { return nil }
        return CGPoint(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height)
    }

    private func tagLabel(for tag: Post.PhotoTag) -> String {
        if let label = tag.label { return label }
        if let user = taggedUsers[tag.userID] {
            return "@\(user.handle)"
        }
        return "@\(tag.userID.prefix(6))"
    }

    private func fetchCommentsPreview() {
        guard let postID = post.id else { return }
        let commentsRef = Firestore.firestore()
            .collection("posts")
            .document(postID)
            .collection("comments")

        commentsRef.getDocuments { snapshot, error in
            if let error = error {
                print("Preview comments fetch error:", error)
                return
            }
            guard let docs = snapshot?.documents else { return }
            commentCount = docs.count
        }

        commentsRef
            .order(by: "timestamp", descending: true)
            .limit(to: 2)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Preview comments fetch error:", error)
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let comments = docs.compactMap { try? $0.data(as: Comment.self) }
                previewComments = comments
            }
    }

    private func fetchTaggedUsers() {
        let ids = post.taggedUserIDs
        guard !ids.isEmpty else { return }
        UserService.shared.fetchUsers(withIDs: ids) { users in
            DispatchQueue.main.async {
                var map: [String: AppUser] = [:]
                for user in users {
                    if let id = user.id {
                        map[id] = user
                    }
                }
                taggedUsers = map
            }
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
}

