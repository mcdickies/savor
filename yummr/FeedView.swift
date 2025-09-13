//
//  FeedView.swift
//  yummr
//
//  Created by kuba woahz on 6/28/25.
//

import SwiftUI
import FirebaseFirestore
//psuh
struct FeedView: View {
    @State private var posts: [Post] = []
    private let db = Firestore.firestore()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(posts.sorted { $0.timestamp > $1.timestamp }) { post in
                        PostCard(post: post)
                    }
                }
                .padding()
            }
            .navigationTitle("The Feed")
            .onAppear {
                fetchPosts()
            }
        }
    }

    func fetchPosts() {
        db.collection("posts")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }
                self.posts = docs.compactMap { try? $0.data(as: Post.self) }
            }
    }
}
