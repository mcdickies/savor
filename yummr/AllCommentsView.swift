//
//  AllCommentsView.swift
//  yummr
//
//  Created by kuba woahz on 6/30/25.
//

import SwiftUI
import FirebaseFirestore


struct AllCommentsView: View {
    let post: Post
    @Environment(\.dismiss) var dismiss
    @State private var comments: [Comment] = []
    @State private var newComment = ""
    @EnvironmentObject var auth: AuthService

    var body: some View {
        NavigationView {
            VStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(comments) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(comment.authorName)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(comment.text)
                                    .font(.body)
                            }
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.top, 4)
                }

                HStack {
                    TextField("Add a comment...", text: $newComment)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button("Send") {
                        addComment()
                    }
                    .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    }

    private func fetchComments() {
        guard let postID = post.id else { return }
        Firestore.firestore()
            .collection("posts").document(postID)
            .collection("comments")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("All comments listener error:", error)
                    return
                }
                guard let docs = snapshot?.documents else { return }
                do {
                    self.comments = try docs.map { try $0.data(as: Comment.self) }
                } catch {
                    print("All comments decode error:", error)
                }
            }
    }

    private func addComment() {
        guard let uid = auth.currentUser?.uid,
              let postID = post.id,
              let name = auth.currentUser?.displayName ?? auth.currentUser?.email else { return }

        let ref = Firestore.firestore()
            .collection("posts").document(postID)
            .collection("comments").document()

        // Let Firestore set the timestamp server-side
        let new = Comment(
            id: ref.documentID,
            text: newComment.trimmingCharacters(in: .whitespacesAndNewlines),
            authorID: uid,
            authorName: name,
            timestamp: nil
        )

        do {
            try ref.setData(from: new)
            newComment = ""
        } catch {
            print("Error posting comment: \(error)")
        }
    }
}
