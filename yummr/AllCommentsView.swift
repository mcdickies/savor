//
//  AllCommentsView.swift
//  yummr
//
//  Created by kuba woahz on 6/30/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseFirestoreSwift

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

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(threads) { thread in
                            commentBlock(thread.comment, isReply: false)
                            ForEach(thread.replies) { reply in
                                commentBlock(reply, isReply: true)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if let replyingTo = replyingTo {
                        HStack {
                            Text("Replying to \(replyingTo.authorName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Cancel") {
                                self.replyingTo = nil
                            }
                            .font(.caption)
                        }
                    }

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
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical)
            }
            .padding(.horizontal)
            .navigationTitle("Comments")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { fetchComments() }
        }
        .onChange(of: newComment, perform: updateMentionSuggestions)
    }

    private func commentBlock(_ comment: Comment, isReply: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                NavigationLink(destination: ProfileView(userID: comment.authorID)) {
                    Text(comment.authorName)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Reply") {
                    replyingTo = comment
                    if !newComment.hasSuffix(" ") { newComment.append(" ") }
                }
                .font(.caption)
            }

            highlightMentions(in: comment.text)
                .font(.body)

            if let timestamp = comment.timestamp {
                Text(timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(8)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(8)
        .padding(.leading, isReply ? 24 : 0)
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

    private func submitComment() {
        guard let uid = auth.currentUser?.uid,
              let postID = post.id,
              let name = auth.currentUser?.displayName ?? auth.currentUser?.email else { return }

        resolveTaggedUserIDs(in: newComment) { taggedIDs in
            let ref: DocumentReference
            var parentID: String? = nil

            if let replyingTo = replyingTo, let parentCommentID = replyingTo.id {
                parentID = parentCommentID
                ref = Firestore.firestore()
                    .collection("posts").document(postID)
                    .collection("comments").document(parentCommentID)
                    .collection("replies").document()
            } else {
                ref = Firestore.firestore()
                    .collection("posts").document(postID)
                    .collection("comments").document()
            }

            let comment = Comment(
                id: ref.documentID,
                text: newComment.trimmingCharacters(in: .whitespacesAndNewlines),
                authorID: uid,
                authorName: name,
                parentCommentID: parentID,
                taggedUserIDs: taggedIDs,
                timestamp: nil
            )

            do {
                try ref.setData(from: comment)
                if parentID == nil {
                    // also add to main comments collection if newly created doc
                } else if let parentID = parentID {
                    // Optionally also write reply reference to parent comment doc for easier queries
                    let parentRef = Firestore.firestore()
                        .collection("posts").document(postID)
                        .collection("comments").document(parentID)
                    parentRef.updateData(["lastRepliedAt": FieldValue.serverTimestamp()])
                }
                newComment = ""
                replyingTo = nil
                mentionSuggestions = []
            } catch {
                print("Error posting comment: \(error)")
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
            .collection("posts").document(postID)
            .collection("comments")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                var updatedThreads: [CommentThread] = []
                let rootComments = docs.compactMap { try? $0.data(as: Comment.self) }
                    .filter { $0.parentCommentID == nil }

                let group = DispatchGroup()
                for var root in rootComments {
                    var thread = CommentThread(comment: root, replies: [])
                    if let commentID = root.id {
                        group.enter()
                        Firestore.firestore()
                            .collection("posts").document(postID)
                            .collection("comments").document(commentID)
                            .collection("replies")
                            .order(by: "timestamp", descending: false)
                            .getDocuments { snapshot, _ in
                                if let replyDocs = snapshot?.documents {
                                    thread.replies = replyDocs.compactMap { try? $0.data(as: Comment.self) }
                                }
                                updatedThreads.append(thread)
                                group.leave()
                            }
                    } else {
                        updatedThreads.append(thread)
                    }
                }

                group.notify(queue: .main) {
                    self.threads = updatedThreads.sorted { (lhs, rhs) in
                        (lhs.comment.timestamp ?? Date.distantPast) < (rhs.comment.timestamp ?? Date.distantPast)
                    }
                }
            }
    }
}
