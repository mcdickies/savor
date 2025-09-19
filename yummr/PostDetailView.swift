//
//  PostDetailView.swift
//  yummr
//
//  Created by kuba woahz on 6/30/25.
//

import SwiftUI
import FirebaseFirestore
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
            VStack(alignment: .leading, spacing: 16) {
                imageCarousel

                if let cookTime = post.cookTime, !cookTime.isEmpty {
                    Label(cookTime, systemImage: "clock")
                        .font(.headline)
                }

                Text(post.description)
                    .font(.body)

                if let recipe = post.recipe, !recipe.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recipe")
                            .font(.title3)
                            .bold()
                        Text(recipe)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                    }
                }

                if let ingredients = post.extraFields?["ingredients"], !ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ingredients")
                            .font(.headline)
                        Text(ingredients)
                            .font(.body)
                    }
                }

                if !post.taggedUserIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tagged")
                            .font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)]) {
                            ForEach(sortedTaggedUsers, id: \.handle) { user in
                                NavigationLink(destination: ProfileView(userID: user.id ?? "")) {
                                    VStack {
                                        Text(user.displayName)
                                            .font(.subheadline)
                                        Text("@\(user.handle)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Divider()

                commentSection
            }
            .padding()
        }
        .navigationTitle(post.title)
        .onAppear {
            fetchComments()
            fetchTaggedUsers()
        }
        .onChange(of: newComment, perform: updateMentionSuggestions)
        .sheet(isPresented: $showAllComments) {
            AllCommentsView(post: post)
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
                    Label(showTagsOverlay ? "Hide tags" : "Show tags", systemImage: showTagsOverlay ? "eye.slash" : "tag")
                }
                .font(.caption)
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
                    .font(.caption2)
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

    private var sortedTaggedUsers: [AppUser] {
        post.taggedUserIDs.compactMap { taggedUsers[$0] }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Comments")
                    .font(.headline)
                Spacer()
                Button("View thread") { showAllComments = true }
                    .font(.caption)
            }

            ForEach(comments) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    NavigationLink(destination: ProfileView(userID: comment.authorID)) {
                        Text(comment.authorName)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    highlightMentions(in: comment.text)
                        .font(.body)
                }
                .padding(8)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Add a comment...", text: $newComment, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                if !mentionSuggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(mentionSuggestions, id: \.handle) { user in
                                Button(action: { insertMention(user) }) {
                                    Text("@\(user.handle)")
                                        .padding(6)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Button("Send") {
                    submitComment()
                }
                .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func highlightMentions(in text: String) -> Text {
        let components = text.split(separator: " ")
        var aggregated = Text("")
        for component in components {
            if component.hasPrefix("@") {
                aggregated = aggregated + Text(" \(component)").foregroundColor(.blue)
            } else {
                aggregated = aggregated + Text(" \(component)")
            }
        }
        return aggregated
    }

    private func updateMentionSuggestions(for text: String) {
        let words = text.split(separator: " ")
        guard let last = words.last, last.hasPrefix("@"), last.count > 1 else {
            mentionSuggestions = []
            return
        }
        let query = last.dropFirst().lowercased()
        UserService.shared.searchUsers(matching: String(query)) { users in
            DispatchQueue.main.async {
                mentionSuggestions = users
                users.forEach { user in
                    if let id = user.id {
                        mentionLookup[user.handle] = id
                    }
                }
            }
        }
    }

    private func insertMention(_ user: AppUser) {
        let handle = user.handle
        var components = newComment.split(separator: " ", omittingEmptySubsequences: false)
        if components.isEmpty {
            newComment = "@\(handle) "
        } else {
            components.removeLast()
            components.append(Substring("@\(handle)"))
            newComment = components.joined(separator: " ") + " "
        }
        mentionSuggestions = []
        if let id = user.id {
            mentionLookup[handle] = id
        }
    }

    private func submitComment() {
        guard let postID = post.id,
              let uid = auth.currentUser?.uid,
              let name = auth.currentUser?.displayName ?? auth.currentUser?.email else { return }

        resolveTaggedUserIDs(in: newComment) { taggedIDs in
            let ref = Firestore.firestore()
                .collection("posts")
                .document(postID)
                .collection("comments")
                .document()

            let comment = Comment(
                id: ref.documentID,
                text: newComment.trimmingCharacters(in: .whitespacesAndNewlines),
                authorID: uid,
                authorName: name,
                parentCommentID: nil,
                taggedUserIDs: taggedIDs,
                timestamp: nil
            )

            do {
                try ref.setData(from: comment)
                newComment = ""
                mentionSuggestions = []
            } catch {
                print("Failed to add comment: \(error)")
            }
        }
    }

    private func resolveTaggedUserIDs(in text: String, completion: @escaping ([String]) -> Void) {
        let handles = Set(text.split(separator: " ").filter { $0.hasPrefix("@") }.map { String($0.dropFirst()) })
        guard !handles.isEmpty else {
            completion([])
            return
        }

        var resolved: [String] = []
        let group = DispatchGroup()

        for handle in handles {
            if let cached = mentionLookup[handle] {
                resolved.append(cached)
                continue
            }
            group.enter()
            UserService.shared.fetchUser(withHandle: handle) { user in
                if let id = user?.id {
                    resolved.append(id)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(Array(Set(resolved)))
        }
    }

    private func fetchComments() {
        guard let postID = post.id else { return }
        Firestore.firestore()
            .collection("posts")
            .document(postID)
            .collection("comments")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                self.comments = docs.compactMap { try? $0.data(as: Comment.self) }
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
