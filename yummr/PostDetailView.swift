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
    @State private var comments: [Comment] = []
    @State private var newComment = ""
    @State private var mentionSuggestions: [AppUser] = []
    @State private var mentionLookup: [String: String] = [:]
    @State private var showAllComments = false
    @State private var showTagsOverlay = false
    @State private var currentImageIndex = 0
    @State private var taggedUsers: [String: AppUser] = [:]
    @EnvironmentObject var auth: AuthService

    private var allImageURLs: [String] {
        post.imageURLs + (post.detailImages ?? [])
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
                if !post.notesList.isEmpty {
                    infoSection(title: "Notes", items: post.notesList)
                }
                if !post.ingredientList.isEmpty {
                    infoSection(title: "Ingredients", items: post.ingredientList)
                }
                if !post.instructionsList.isEmpty {
                    instructionsSection
                } else if let recipeText = post.recipe, !recipeText.isEmpty {
                    Text(recipeText)
                        .appTextStyle(.body)
                        .foregroundColor(.primary)
                }
                commentSection
            }
            .padding()
        }
        .navigationTitle(post.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchComments()
            fetchTaggedUsers()
        }
        .onChange(of: newComment, perform: updateMentionSuggestions)
        .sheet(isPresented: $showAllComments) {
            AllCommentsView(post: post)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(post.title)
                    .appTextStyle(.title2, weight: .bold)
                    .foregroundColor(.primary)
                Spacer()
                if let rating = post.starRating {
                    StarRatingView(rating: rating)
                }
                if post.isFavorited {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }
            Text("by \(post.authorName)")
                .appTextStyle(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var captionText: String? {
        let trimmed = post.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var metaRow: some View {
        let cookTime = post.cookTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let calories = post.formattedCalories
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

            if !post.photoTags.isEmpty {
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
            ForEach(Array(post.instructionsList.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)")
                    .appTextStyle(.body)
                    .foregroundColor(.primary)
            }
        }
    }

    private func mappedIndex(from displayedIndex: Int) -> Int {
        if displayedIndex < post.imageURLs.count {
            return displayedIndex
        } else {
            return displayedIndex - post.imageURLs.count
        }
    }

    private func tags(for imageIndex: Int) -> [Post.PhotoTag] {
        post.photoTags.filter { tag in
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
                        Text(comment.authorName)
                            .appTextStyle(.caption, weight: .semibold)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)

                    highlightMentions(in: comment.text)
                        .appTextStyle(.callout)

                    Text(comment.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .appTextStyle(.caption2)
                        .foregroundColor(.secondary)
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
            if !mentionSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(mentionSuggestions, id: \.id) { suggestion in
                            Button {
                                insertMention(suggestion)
                            } label: {
                                Text("@\(suggestion.handle)")
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

    private func fetchComments() {
        guard let postID = post.id else { return }
        Firestore.firestore()
            .collection("posts")
            .document(postID)
            .collection("comments")
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching comments: \(error)")
                    return
                }

                guard let docs = snapshot?.documents else { return }
                do {
                    comments = try docs.map { try $0.data(as: Comment.self) }
                } catch {
                    print("Failed to decode comments: \(error)")
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

    private func insertMention(_ user: AppUser) {
        let handle = "@\(user.handle)"
        let trimmed = newComment.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            newComment = handle + " "
        } else {
            newComment += " " + handle + " "
        }
        mentionSuggestions = []
        mentionLookup[handle] = user.id
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
            }
        }
    }

    private func postComment() {
        guard let postID = post.id else { return }
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var payload: [String: Any] = [
            "text": text,
            "timestamp": Timestamp(date: Date())
        ]

        if let user = auth.currentUser {
            payload["authorID"] = user.id
            payload["authorName"] = user.displayName
        }

        let mentions = mentionLookup
        if !mentions.isEmpty {
            payload["mentionedUsers"] = mentions
        }

        Firestore.firestore()
            .collection("posts")
            .document(postID)
            .collection("comments")
            .addDocument(data: payload) { error in
                if let error = error {
                    print("Error posting comment: \(error)")
                    return
                }

                newComment = ""
                mentionSuggestions = []
                mentionLookup = [:]
                fetchComments()
            }
    }
}
