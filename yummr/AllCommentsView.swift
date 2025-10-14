import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import UIKit

struct CommentThread: Identifiable {
    let comment: Comment
    var replies: [Comment]

    var id: String { comment.id ?? UUID().uuidString }
}

struct AllCommentsView: View {
    let post: Post
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var auth: AuthService

    @State private var threads: [CommentThread] = []
    @State private var newComment = ""
    @State private var replyingTo: Comment?
    @State private var mentionSuggestions: [AppUser] = []
    @State private var mentionLookup: [String: String] = [:]
    @State private var dragOffset: CGFloat = 0

    @State private var rootListener: ListenerRegistration?
    @State private var replyListeners: [String: ListenerRegistration] = [:]
    @State private var repliesCache: [String: [Comment]] = [:]

    private let db = Firestore.firestore()

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)

                header
                    .padding(.top, 8)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(threads) { thread in
                                VStack(alignment: .leading, spacing: 8) {
                                    commentBlock(thread.comment, isReply: false)
                                    ForEach(thread.replies) { reply in
                                        commentBlock(reply, isReply: true)
                                    }
                                }
                                .id(thread.id)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 80)
                    }
                    .onChange(of: threads.count) { _ in
                        if replyingTo == nil {
                            if let lastID = threads.last?.id {
                                withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                            }
                        }
                    }
                }

                composer
                    .padding(.horizontal)
                    .padding(.bottom, 24)
            }
            .background(.ultraThinMaterial)
            .cornerRadius(24, corners: [.topLeft, .topRight])
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        if value.translation.height > 100 {
                            dismiss()
                        }
                        dragOffset = 0
                    }
            )
            .frame(maxHeight: UIScreen.main.bounds.height * 0.85)
        }
        .onAppear(perform: startListening)
        .onDisappear(perform: teardownListeners)
        .onChange(of: newComment, perform: updateMentionSuggestions)
    }

    private var header: some View {
        HStack {
            Text("Comments")
                .font(.headline)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.headline)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func commentBlock(_ comment: Comment, isReply: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                NavigationLink(destination: ProfileView(userID: comment.authorID)) {
                    Text(HandleFormatter.normalizedHandle(from: comment.authorName))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)

                Spacer()

                if canDelete(comment: comment) {
                    Menu {
                        Button(role: .destructive) {
                            delete(comment: comment)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .foregroundColor(.secondary)
                    }
                }
            }

            highlightMentions(in: comment.text)
                .font(.body)

            HStack(spacing: 12) {
                if let timestamp = comment.timestamp {
                    Text(timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Reply") {
                    replyingTo = comment
                }
                .font(.caption)
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(UIColor.systemBackground).opacity(0.8))
        .cornerRadius(12)
        .padding(.leading, isReply ? 32 : 0)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyingTo {
                HStack {
                    Text("Replying to \(HandleFormatter.normalizedHandle(from: replyingTo.authorName))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Cancel") { self.replyingTo = nil }
                        .font(.caption)
                }
            }

            TextField("Add a comment…", text: $newComment, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            if !mentionSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mentionSuggestions, id: \.id) { user in
                            Button {
                                insertMention(user)
                            } label: {
                                Text(HandleFormatter.normalizedHandle(from: user.handle))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(10)
                            }
                        }
                    }
                }
            }

            Button("Send", action: submitComment)
                .buttonStyle(.borderedProminent)
                .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func highlightMentions(in text: String) -> Text {
        let components = text.split(separator: " ")
        var aggregated = Text("")
        for (index, component) in components.enumerated() {
            if index > 0 {
                aggregated = aggregated + Text(" ")
            }
            if component.hasPrefix("@") {
                aggregated = aggregated + Text(String(component)).foregroundColor(.accentColor)
            } else {
                aggregated = aggregated + Text(String(component))
            }
        }
        return aggregated
    }

    private func insertMention(_ user: AppUser) {
        let normalizedHandle = HandleFormatter.normalizedHandle(from: user.handle)
        guard normalizedHandle.count > 1 else { return }
        if let id = user.id {
            mentionLookup[String(normalizedHandle.dropFirst())] = id
        }

        var tokens = newComment.split(separator: " ", omittingEmptySubsequences: false)
        if tokens.isEmpty {
            newComment = normalizedHandle + " "
        } else {
            tokens.removeLast()
            tokens.append(Substring(normalizedHandle))
            newComment = tokens.joined(separator: " ") + " "
        }
        mentionSuggestions = []
    }

    private func updateMentionSuggestions(for text: String) {
        let words = text.split(separator: " ")
        guard let last = words.last, last.hasPrefix("@"), last.count > 1 else {
            mentionSuggestions = []
            return
        }
        let query = last.dropFirst().lowercased()
        UserService.shared.searchUsers(matching: String(query), limit: 5, includeBio: false) { users in
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

    private func submitComment() {
        guard let uid = auth.currentUser?.uid, let postID = post.id else { return }
        let trimmedComment = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedComment.isEmpty else { return }

        let fallbackName = auth.currentUser?.displayName ?? auth.currentUser?.email ?? "Anonymous"
        UserService.shared.fetchUser(withID: uid) { appUser in
            let authorHandle = HandleFormatter.normalizedHandle(from: appUser?.handle) ?? HandleFormatter.normalizedHandle(from: fallbackName)

            resolveTaggedUserIDs(in: trimmedComment) { taggedIDs in
                var ref: DocumentReference
                var parentID: String?

                if let replyingTo = replyingTo, let parentCommentID = replyingTo.id {
                    parentID = parentCommentID
                    ref = db.collection("posts").document(postID)
                        .collection("comments").document(parentCommentID)
                        .collection("replies").document()
                } else {
                    ref = db.collection("posts").document(postID)
                        .collection("comments").document()
                }

                let comment = Comment(
                    id: ref.documentID,
                    text: trimmedComment,
                    authorID: uid,
                    authorName: authorHandle,
                    parentCommentID: parentID,
                    taggedUserIDs: taggedIDs,
                    timestamp: Date()
                )

                do {
                    try ref.setData(from: comment)
                    DispatchQueue.main.async {
                        newComment = ""
                        replyingTo = nil
                        mentionSuggestions = []
                    }
                } catch {
                    print("Error posting comment: \(error)")
                }
            }
        }
    }

    private func resolveTaggedUserIDs(in text: String, completion: @escaping ([String]) -> Void) {
        let handles = Set(text.split(separator: " ")
            .filter { $0.hasPrefix("@") }
            .map { String($0.dropFirst()) })

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

    private func startListening() {
        guard let postID = post.id else { return }
        rootListener = db.collection("posts")
            .document(postID)
            .collection("comments")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                var updatedThreads: [CommentThread] = []
                var newListeners: [String: ListenerRegistration] = [:]

                let rootComments = docs.compactMap { try? $0.data(as: Comment.self) }
                    .filter { $0.parentCommentID == nil }

                for root in rootComments {
                    var thread = CommentThread(comment: root, replies: [])
                    if let commentID = root.id {
                        thread.replies = repliesCache[commentID] ?? []
                        if replyListeners[commentID] == nil {
                            let listener = db.collection("posts")
                                .document(postID)
                                .collection("comments")
                                .document(commentID)
                                .collection("replies")
                                .order(by: "timestamp", descending: false)
                                .addSnapshotListener { snapshot, _ in
                                    guard let replyDocs = snapshot?.documents else { return }
                                    let replies = replyDocs.compactMap { try? $0.data(as: Comment.self) }
                                    DispatchQueue.main.async {
                                        repliesCache[commentID] = replies
                                        threads = threads.map { existing in
                                            guard existing.comment.id == commentID else { return existing }
                                            return CommentThread(comment: existing.comment, replies: replies)
                                        }
                                    }
                                }
                            newListeners[commentID] = listener
                        }
                    }
                    updatedThreads.append(thread)
                }

                replyListeners.merge(newListeners) { current, _ in
                    current
                }

                let activeIDs = Set(rootComments.compactMap { $0.id })
                replyListeners.keys
                    .filter { !activeIDs.contains($0) }
                    .forEach { key in
                        replyListeners[key]?.remove()
                        replyListeners.removeValue(forKey: key)
                        repliesCache.removeValue(forKey: key)
                    }

                DispatchQueue.main.async {
                    threads = updatedThreads.sorted { lhs, rhs in
                        (lhs.comment.timestamp ?? .distantPast) < (rhs.comment.timestamp ?? .distantPast)
                    }
                }
            }
    }

    private func teardownListeners() {
        rootListener?.remove()
        replyListeners.values.forEach { $0.remove() }
        replyListeners.removeAll()
    }

    private func canDelete(comment: Comment) -> Bool {
        guard let currentUserID = auth.currentUser?.uid else { return false }
        if comment.authorID == currentUserID { return true }
        return post.authorID == currentUserID
    }

    private func delete(comment: Comment) {
        guard let postID = post.id, let commentID = comment.id else { return }
        let postRef = db.collection("posts").document(postID)
        if comment.parentCommentID == nil {
            let commentRef = postRef.collection("comments").document(commentID)
            commentRef.collection("replies").getDocuments { snapshot, _ in
                snapshot?.documents.forEach { $0.reference.delete() }
                commentRef.delete()
            }
        } else if let parentID = comment.parentCommentID {
            postRef.collection("comments")
                .document(parentID)
                .collection("replies")
                .document(commentID)
                .delete()
        }
    }
}
