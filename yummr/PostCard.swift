import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFirestoreSwift

struct PostCard: View {
    var post: Post
    @State private var likeCount: Int
    @State private var isLiked: Bool
    @State private var isProcessingLike = false
    @State private var previewComments: [Comment] = []
    @State private var showAllComments = false
    @State private var commentCount = 0
    @State private var showTagsOverlay = false
    @State private var currentImageIndex = 0
    @State private var taggedUsers: [String: AppUser] = [:]

    init(post: Post) {
        self.post = post
        _likeCount = State(initialValue: post.likeCount)
        _isLiked = State(initialValue: post.likedBy.contains(Auth.auth().currentUser?.uid ?? ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.title)
                .font(.headline)

            NavigationLink(destination: ProfileView(userID: post.authorID)) {
                Text("By \(post.authorName)")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            tabbedImages

            if let cookTime = post.cookTime, !cookTime.isEmpty {
                Label(cookTime, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(post.description)
                .font(.body)

            if !post.taggedUserIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(sortedTaggedUsers, id: \.handle) { user in
                            NavigationLink(destination: ProfileView(userID: user.id ?? "")) {
                                Text("@\(user.handle)")
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button(action: toggleLike) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundColor(isLiked ? .red : .gray)
                }
                Text("\(likeCount)")
                    .foregroundColor(.gray)
                    .font(.subheadline)

                Spacer()

                if !post.photoTags.isEmpty {
                    Button {
                        withAnimation {
                            showTagsOverlay.toggle()
                        }
                    } label: {
                        Image(systemName: showTagsOverlay ? "tag.fill" : "tag")
                    }
                }
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(previewComments.prefix(2)) { comment in
                    commentRow(comment)
                }

                if commentCount > 2 {
                    Button("View all comments") {
                        showAllComments = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }

                Button("Open comments") {
                    showAllComments = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
        .onAppear {
            fetchPreviewComments()
            fetchTaggedUsers()
        }
        .sheet(isPresented: $showAllComments, onDismiss: {
            fetchPreviewComments()
        }) {
            AllCommentsView(post: post)
        }
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
                .cornerRadius(12)
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
                    .font(.caption2)
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

    private var sortedTaggedUsers: [AppUser] {
        post.taggedUserIDs.compactMap { taggedUsers[$0] }
    }

    private func commentRow(_ comment: Comment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NavigationLink(destination: ProfileView(userID: comment.authorID)) {
                Text(comment.authorName)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            highlightMentions(in: comment.text)
                .font(.caption)
        }
    }

    private func highlightMentions(in text: String) -> Text {
        let parts = text.split(separator: " ")
        var composed = Text("")
        for part in parts {
            if part.hasPrefix("@") {
                let mention = String(part)
                composed = composed + Text(" \(mention)").foregroundColor(.blue)
            } else {
                composed = composed + Text(" \(part)")
            }
        }
        return composed
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
            .limit(to: 5)
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
                self.taggedUsers = map
            }
        }
    }
}
