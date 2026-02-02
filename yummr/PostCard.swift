import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct PostCard: View {
    var post: Post
    var onOpenDetails: (() -> Void)?
    @State private var likeCount: Int
    @State private var isLiked: Bool
    @State private var isProcessingLike = false
    @State private var showAllComments = false
    @State private var commentCount = 0
    @State private var showTagsOverlay = false
    @State private var taggedUsers: [String: AppUser] = [:]
    @State private var previewComments: [Comment] = []
    @State private var isSaved = false
    @State private var author: AppUser?
    @State private var isShareSheetPresented = false
    @State private var shareItems: [Any] = []

    init(post: Post, onOpenDetails: (() -> Void)? = nil) {
        self.post = post
        self.onOpenDetails = onOpenDetails
        _likeCount = State(initialValue: post.likeCount)
        _isLiked = State(initialValue: post.likedBy.contains(Auth.auth().currentUser?.uid ?? ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            titleRow

            detailTapArea

            if !post.photoTags.isEmpty {
                Button {
                    withAnimation(.easeInOut) {
                        showTagsOverlay.toggle()
                    }
                } label: {
                    Label(showTagsOverlay ? "Hide tags" : "Show tags", systemImage: showTagsOverlay ? "tag.fill" : "tag")
                        .appTextStyle(.footnote, weight: .medium)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

            interactionBar

            if !previewComments.isEmpty {
                commentPreview
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            fetchCommentsPreview()
            fetchTaggedUsers()
            checkSaveState()
            fetchAuthor()
            refreshLikeState()
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheet(activityItems: shareItems)
        }
        .sheet(isPresented: $showAllComments, onDismiss: {
            fetchCommentsPreview()
        }) {
            AllCommentsView(post: post)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            NavigationLink(destination: ProfileView(userID: post.authorID)) {
                avatarView
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                NavigationLink(destination: ProfileView(userID: post.authorID)) {
                    Text(primaryAuthorName)
                        .appTextStyle(.subheadline, weight: .semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                Text(authorMetadataText)
                    .appTextStyle(.footnote)
                    .foregroundColor(Color(.tertiaryLabel))
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Button("Share") {
                    prepareShareSheet()
                }
                Button("Report", role: .destructive) {
                    // TODO: report implementation
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(.tertiaryLabel))
                    .padding(8)
                    .contentShape(Rectangle())
            }
        }
    }

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(post.title)
                    .appTextStyle(.headline, weight: .semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer()

                if let rating = post.starRating {
                    StarRatingView(rating: rating)
                }
            }

            if let caption = captionText {
                Text(caption)
                    .appTextStyle(.subheadline)
                    .foregroundColor(Color(.secondaryLabel))
                    .lineLimit(2)
            }
        }
    }

    private var interactionBar: some View {
        HStack(alignment: .center, spacing: 0) {
            interactionButton(
                label: Label("\(likeCount)", systemImage: isLiked ? "heart.fill" : "heart"),
                tint: isLiked ? .red : Color(.label)
            ) {
                toggleLike()
            }

            interactionSeparator

            interactionButton(
                label: Label(commentCount > 0 ? "\(commentCount)" : "Comment", systemImage: "bubble.right"),
                tint: Color(.label)
            ) {
                showAllComments = true
            }

            interactionSeparator

            interactionButton(
                label: Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark"),
                tint: isSaved ? .accentColor : Color(.label)
            ) {
                toggleSave()
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var interactionSeparator: some View {
        Text("•")
            .appTextStyle(.footnote, weight: .semibold)
            .foregroundColor(Color(.tertiaryLabel))
            .padding(.horizontal, 12)
    }

    private func interactionButton(label: Label<Text, Image>, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .labelStyle(.titleAndIcon)
                .appTextStyle(.footnote, weight: .medium)
                .foregroundColor(tint)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var commentPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(previewComments) { comment in
                VStack(alignment: .leading, spacing: 2) {
                    Text(commentAuthor(for: comment))
                        .appTextStyle(.footnote, weight: .semibold)
                        .foregroundColor(Color(.secondaryLabel))

                    Text(comment.text)
                        .appTextStyle(.footnote)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
            }

            Button {
                showAllComments = true
            } label: {
                Text(commentPreviewLabel)
                    .appTextStyle(.footnote, weight: .semibold)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private var commentPreviewLabel: String {
        switch commentCount {
        case 1:
            return "View 1 comment"
        case let count where count > 1:
            return "View all comments (\(count))"
        default:
            return "View comments"
        }
    }

    private func toggleSave() {
        let previous = isSaved
        isSaved.toggle()
        SavedService.shared.toggleSave(post: post) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let saved):
                    self.isSaved = saved
                case .failure(let error):
                    print("Failed to save post: \(error)")
                    self.isSaved = previous
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

    private var imageCarousel: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width * 0.95
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(post.imageURLs.enumerated()), id: \.offset) { item in
                        ZStack {
                            CachedWebImage(url: URL(string: item.element)) {
                                ProgressView()
                            }
                            .scaledToFill()
                            .frame(width: width, height: height)
                            .clipped()

                            if showTagsOverlay {
                                ForEach(tags(for: item.offset), id: \.id) { tag in
                                    tagOverlay(tag: tag, size: CGSize(width: width, height: height))
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
        .frame(height: UIScreen.main.bounds.width * 0.95)
    }

    @ViewBuilder
    private var detailTapArea: some View {
        if let onOpenDetails {
            Button(action: onOpenDetails) {
                imageCarousel
            }
            .buttonStyle(.plain)
        } else {
            imageCarousel
        }
    }

    private func tagOverlay(tag: Post.PhotoTag, size: CGSize) -> some View {
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
            DispatchQueue.main.async {
                commentCount = docs.count
            }
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
                let comments = docs
                    .compactMap { try? $0.data(as: Comment.self) }
                    .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
                DispatchQueue.main.async {
                    previewComments = comments
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
                taggedUsers = map
            }
        }
    }

    private func fetchAuthor() {
        guard author == nil else { return }
        UserService.shared.fetchUser(withID: post.authorID) { user in
            DispatchQueue.main.async {
                self.author = user
            }
        }
    }

    private func prepareShareSheet() {
        var items: [Any] = [post.title]
        let trimmedDescription = post.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDescription.isEmpty {
            items.append(trimmedDescription)
        }
        if let urlString = post.imageURLs.first, let url = URL(string: urlString) {
            items.append(url)
        }
        shareItems = items
        isShareSheetPresented = !items.isEmpty
    }

    private var primaryAuthorName: String {
        if let displayName = author?.displayName.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
            return displayName
        }
        let trimmedPostName = post.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPostName.isEmpty ? "Unknown Chef" : trimmedPostName
    }

    private var authorMetadataText: String {
        var components: [String] = []
        if let handle = resolvedHandle,
           handle.caseInsensitiveCompare(primaryAuthorName) != .orderedSame {
            components.append(handle)
        }
        components.append(relativeTimestamp)
        return components.joined(separator: " • ")
    }

    private var resolvedHandle: String? {
        if let normalizedHandle = HandleFormatter.normalizedHandleIfPresent(author?.handle) {
            return normalizedHandle
        }

        let trimmedAuthorName = post.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAuthorName.isEmpty else { return nil }

        if trimmedAuthorName.contains("@"), !trimmedAuthorName.contains(" ") {
            return trimmedAuthorName
        }

        let normalized = HandleFormatter.normalizedHandle(from: trimmedAuthorName)
        return normalized == "@" ? nil : normalized
    }

    private var relativeTimestamp: String {
        let formatter = Self.relativeFormatter
        return formatter.localizedString(for: post.timestamp, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var avatarView: some View {
        Group {
            if let urlString = author?.profileImageURL, let url = URL(string: urlString) {
                CachedWebImage(url: url) {
                    Circle().fill(Color(.tertiarySystemFill))
                }
                .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color(.tertiaryLabel))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private func commentAuthor(for comment: Comment) -> String {
        let normalized: String = HandleFormatter.normalizedHandle(from: comment.authorName)
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "@" {
            return "Unknown"
        }
        return trimmed
    }

    private func toggleLike() {
        guard !isProcessingLike else { return }
        isProcessingLike = true
        let previousLiked = isLiked
        let previousCount = likeCount
        isLiked.toggle()
        likeCount += isLiked ? 1 : -1

        PostService.shared.toggleLike(for: post) { result in
            DispatchQueue.main.async {
                switch result {
                case .success():
                    break
                case .failure(let error):
                    print("Failed to like post: \(error)")
                    isLiked = previousLiked
                    likeCount = previousCount
                }
                isProcessingLike = false
            }
        }
    }

    private func refreshLikeState() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLiked = post.likedBy.contains(uid)
    }
}
