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
    @EnvironmentObject var auth: AuthService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AsyncImage(url: URL(string: post.imageURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                default:
                    Color.gray.frame(height: 200)
                }
            }

            Text(post.title)
                .font(.title2)
                .bold()

            Text(post.description)
                .font(.body)

            Divider()

            Text("Comments")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(comment.authorName)
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(comment.text)
                        }
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
            }

            HStack {
                TextField("Add a comment...", text: $newComment)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Send") {
                    addComment()
                }
                .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .navigationTitle("Post")
        .onAppear {
            fetchComments()
        }
    }

    private func fetchComments() {
        guard let postID = post.id else { return }
        let ref = Firestore.firestore()
            .collection("posts")
            .document(postID)
            .collection("comments")
            .order(by: "timestamp", descending: false)

        ref.addSnapshotListener { snapshot, _ in
            guard let docs = snapshot?.documents else { return }
            self.comments = docs.compactMap { try? $0.data(as: Comment.self) }
        }
    }

    private func addComment() {
        guard let postID = post.id,
              let uid = auth.currentUser?.uid,
              let name = auth.currentUser?.displayName ?? auth.currentUser?.email else { return }

        let ref = Firestore.firestore()
            .collection("posts")
            .document(postID)
            .collection("comments")
            .document()

        let new = Comment(id: ref.documentID, text: newComment, authorID: uid, authorName: name, timestamp: Date())

        do {
            try ref.setData(from: new)
            newComment = ""
        } catch {
            print("Failed to add comment: \(error)")
        }
    }
}
