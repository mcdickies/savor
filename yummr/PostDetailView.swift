//
//  PostDetailView.swift
//  yummr
//
//  Created by kuba woahz on 6/30/25.
//

import SwiftUI
import FirebaseFirestore

struct PostDetailView: View {
    let post: Post
    @State private var livePost: Post
    @State private var comments: [Comment] = []
    @State private var newComment = ""
    @State private var mentionSuggestions: [AppUser] = []
    @State private var mentionLookup: [String: String] = [:]
    @State private var showAllComments = false
    @State private var showTagsOverlay = false
    @State private var currentImageIndex = 0
    @State private var taggedUsers: [String: AppUser] = [:]
    @State private var showEdit = false
    @State private var postListener: ListenerRegistration?
    @State private var commentsListener: ListenerRegistration?
    @State private var isSaved = false
    @EnvironmentObject var auth: AuthService

    init(post: Post) {
        self.post = post
        _livePost = State(initialValue: post)
    }

    private var allImageURLs: [String] {
        livePost.imageURLs + (livePost.detailImages ?? [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                imageCarousel
                if let caption = captionText {
                    Text(caption)
                        .appTextStyle(.body)
                        .foregroundColor(.primary)
                }
                metaRow
                if !livePost.notesList.isEmpty {
                    infoSection(title: "Notes", items: livePost.notesList)
                }
                if !livePost.ingredientList.isEmpty {
                    infoSection(title: "Ingredients", items: livePost.ingredientList)
                }
                if !livePost.instructionsList.isEmpty {
                    instructionsSection
                } else if let recipeText = livePost.recipe, !recipeText.isEmpty {
                    Text(recipeText)
                        .appTextStyle(.body)
                        .foregroundColor(.primary)
                }
                commentSection
            }
            .padding()
        }
        .navigationTitle(livePost.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            listenToPost()
            listenToComments()
            fetchTaggedUsers()
            checkSaveState()
        }
        .onChange(of: newComment, perform: updateMentionSuggestions)
        .onChange(of: livePost.taggedUserIDs) { _ in
            fetchTaggedUsers()
        }
        .onChange(of: livePost.id) { _ in
            checkSaveState()
        }
        .sheet(isPresented: $showAllComments) {
            AllCommentsView(post: livePost)
        }
        .sheet(isPresented: $showEdit) {
            EditPostView(post: $livePost)
        }
        .onDisappear(perform: teardownListeners)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    toggleSave()
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                }

                if auth.currentUser?.uid == livePost.authorID {
                    Button("Edit") { showEdit = true }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(livePost.title)
                    .appTextStyle(.title2, weight: .bold)
                    .foregroundColor(.primary)
                Spacer()
                if let rating = livePost.starRating {
                    StarRatingView(rating: rating)
                }
                if livePost.isFavorited {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }

            NavigationLink(destination: ProfileView(userID: livePost.authorID)) {
                Text("by \(HandleFormatter.normalizedHandle(from: livePost.authorName))")
                    .appTextStyle(.caption)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private var captionText: String? {
        let trimmed = livePost.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var metaRow: some View {
        let cookTime = livePost.cookTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let calories = livePost.formattedCalories
        return HStack(spacing: 16) {
            if let cookTime, !cookTime.isEmpty {
                Label(cookTime, systemImage: "clock")
                    .appTextStyle(.subheadline, weight: .medium)
                    .foregroundColor(.secondary)
            }
            if let calories {
                Label(calories, systemImage: "flame")
                    .appTextStyle(.subheadline, weight: .medium)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var imageCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabView(selection: $currentImageIndex) {
                ForEach(Array(allImageURLs.enumerated()), id: \.offset) { item in
                    GeometryReader { geometry in
                        ZStack {
                            CachedWebImage(url: URL(string: item.element)) {
                                ProgressView()
                            }
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()

                            if showTagsOverlay {
                                ForEach(tags(for: mappedIndex(from: item.offset)), id: \.id) { tag in
                                    tagOverlay(tag: tag, geometry: geometry)
                                }
                            }
                        }
                    }
                    .frame(height: 320)
                    .tag(item.offset)
                }
            }
            .frame(height: 320)
            .tabViewStyle(PageTabViewStyle())

            if !livePost.photoTags.isEmpty {
                Button {
                    withAnimation { showTagsOverlay.toggle() }
                } label: {
                    Label(showTagsOverlay ? "Hide tags" : "Show tags", systemImage: showTagsOverlay ? "tag.fill" : "tag")
                        .appTextStyle(.caption, weight: .medium)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func infoSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appTextStyle(.headline, weight: .semibold)
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .appTextStyle(.body)
                    .foregroundColor(.primary)
            }
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions")
                .appTextStyle(.headline, weight: .semibold)
            ForEach(Array(livePost.instructionsList.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)")
                    .appTextStyle(.body)
                    .foregroundColor(.primary)
            }
        }
    }

    private func mappedIndex(from displayedIndex: Int) -> Int {
        if displayedIndex < livePost.imageURLs.count {
            return displayedIndex
        } else {
            return displayedIndex - livePost.imageURLs.count
        }
    }

    private func tags(for imageIndex: Int) -> [Post.PhotoTag] {
        livePost.photoTags.filter { tag in
            guard let index = tag.imageIndex else { return false }
            return index == imageIndex
        }
    }

    private func tagOverlay(tag: Post.PhotoTag, geometry: GeometryProxy) -> some View {
        let size = geometry.size
        let position = position(for: tag, in: size)
        return Group {
            if let position = position {
                Text(tagLabel(for: tag))
                    .appTextStyle(.caption2, weight: .semibold)
                    .padding(6)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .position(position)
            }
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

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Comments")
                    .appTextStyle(.headline, weight: .semibold)
                Spacer()
                Button("View thread") { showAllComments = true }
                    .appTextStyle(.caption, weight: .medium)
            }

            ForEach(comments) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    NavigationLink(destination: ProfileView(userID: comment.authorID)) {
                        Text(HandleFormatter.normalizedHandle(from: comment.authorName))
                            .appTextStyle(.caption, weight: .semibold)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)

                    highlightMentions(in: comment.text)
                        .appTextStyle(.callout)

                    if let timestamp = comment.timestamp {
                        Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                            .appTextStyle(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 6)
                Divider()
            }

            commentComposer
        }
    }

    private var commentComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a comment")
                .appTextStyle(.subheadline, weight: .semibold)
            TextField("Share your thoughts…", text: $newComment, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit(postComment)
            if !mentionSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(mentionSuggestions, id: \.id) { suggestion in
                            Button {
                                insertMention(suggestion)
                            } label: {
                                Text(HandleFormatter.normalizedHandle(from: suggestion.handle))
                                    .appTextStyle(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
            }
            Button("Post Comment", action: postComment)
                .buttonStyle(.borderedProminent)
                .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func highlightMentions(in text: String) -> Text {
        let parts = text.split(separator: " ")
        var composed = Text("")
        for (index, part) in parts.enumerated() {
            if index > 0 {
                composed = composed + Text(" ")
            }
            if part.hasPrefix("@") {
                let mention = String(part)
                composed = composed + Text(mention).foregroundColor(.accentColor)
            } else {
                composed = composed + Text(String(part))
            }
        }
        return composed
    }

    private func fetchTaggedUsers() {
        let ids = livePost.taggedUserIDs
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

    private func insertMention(_ user: AppUser) {
        let handle = HandleFormatter.normalizedHandle(from: user.handle)
        guard handle.count > 1 else { return }
        let trimmed = newComment.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            newComment = handle + " "
        } else {
            newComment += " " + handle + " "
        }
        mentionSuggestions = []
        if let id = user.id {
            let bare = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
            mentionLookup[bare.lowercased()] = id
        }
    }

    private func updateMentionSuggestions(_ text: String) {
        guard let lastWord = text.split(separator: " ").last, lastWord.hasPrefix("@") else {
            mentionSuggestions = []
            return
        }

        let query = lastWord.replacingOccurrences(of: "@", with: "")
        guard !query.isEmpty else {
            mentionSuggestions = []
            return
        }

        UserService.shared.searchUsers(matching: String(query)) { users in
            DispatchQueue.main.async {
                mentionSuggestions = users
                for user in users {
                    if let id = user.id {
                        mentionLookup[user.handle.lowercased()] = id
                    }
                }
            }
        }
    }

    private func postComment() {
        guard let postID = livePost.id ?? post.id,
              let user = auth.currentUser else { return }

        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let fallbackName = user.displayName ?? user.email ?? "Anonymous"

        UserService.shared.fetchUser(withID: user.uid) { appUser in
            let authorHandle = HandleFormatter.normalizedHandleIfPresent(appUser?.handle)
                ?? HandleFormatter.normalizedHandle(from: fallbackName)

            resolveTaggedUserIDs(in: text) { taggedIDs in
                let collection = Firestore.firestore()
                    .collection("posts")
                    .document(postID)
                    .collection("comments")

                let document = collection.document()
                let comment = Comment(
                    id: document.documentID,
                    text: text,
                    authorID: user.uid,
                    authorName: authorHandle,
                    parentCommentID: nil,
                    taggedUserIDs: taggedIDs,
                    timestamp: Date()
                )

                do {
                    try document.setData(from: comment)
                    DispatchQueue.main.async {
                        newComment = ""
                        mentionSuggestions = []
                        mentionLookup = [:]
                    }
                } catch {
                    print("Error posting comment: \(error)")
                }
            }
        }
    }

    private func resolveTaggedUserIDs(in text: String, completion: @escaping ([String]) -> Void) {
        var uniqueHandles: [String: String] = [:]
        for token in text.split(separator: " ") where token.hasPrefix("@") {
            let stripped = String(token.dropFirst())
            guard !stripped.isEmpty else { continue }
            let lower = stripped.lowercased()
            if uniqueHandles[lower] == nil {
                uniqueHandles[lower] = stripped
            }
        }

        guard !uniqueHandles.isEmpty else {
            completion([])
            return
        }

        let syncQueue = DispatchQueue(label: "PostDetailView.resolveTaggedUserIDs")
        var resolved: [String] = []
        let group = DispatchGroup()

        func appendResolved(_ id: String) {
            syncQueue.async {
                resolved.append(id)
            }
        }

        for (lower, original) in uniqueHandles {
            if let cached = mentionLookup[lower] {
                appendResolved(cached)
                continue
            }

            group.enter()
            UserService.shared.fetchUser(withHandle: original) { user in
                if let id = user?.id {
                    appendResolved(id)
                    DispatchQueue.main.async {
                        mentionLookup[lower] = id
                    }
                    group.leave()
                    return
                }

                let fallback = original.lowercased()
                guard fallback != original else {
                    group.leave()
                    return
                }

                UserService.shared.fetchUser(withHandle: fallback) { fallbackUser in
                    if let id = fallbackUser?.id {
                        appendResolved(id)
                        DispatchQueue.main.async {
                            mentionLookup[lower] = id
                        }
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            var final: [String] = []
            syncQueue.sync {
                final = resolved
            }
            completion(Array(Set(final)))
        }
    }

    private func toggleSave() {
        SavedService.shared.toggleSave(post: livePost) { result in
            DispatchQueue.main.async {
                if case .success(let saved) = result {
                    self.isSaved = saved
                }
            }
        }
    }

    private func checkSaveState() {
        guard let postID = livePost.id ?? post.id else { return }
        SavedService.shared.isPostSaved(postID: postID) { saved in
            DispatchQueue.main.async {
                self.isSaved = saved
            }
        }
    }

    private func listenToPost() {
        guard let postID = post.id else { return }
        postListener = Firestore.firestore()
            .collection("posts")
            .document(postID)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot = snapshot else { return }
                if let updated = try? snapshot.data(as: Post.self) {
                    DispatchQueue.main.async {
                        self.livePost = updated
                    }
                }
            }
    }

    private func listenToComments() {
        guard let postID = post.id else { return }
        commentsListener = Firestore.firestore()
            .collection("posts")
            .document(postID)
            .collection("comments")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let resolved = docs.compactMap { try? $0.data(as: Comment.self) }
                DispatchQueue.main.async {
                    self.comments = resolved
                }
            }
    }

    private func teardownListeners() {
        postListener?.remove()
        commentsListener?.remove()
    }
}
