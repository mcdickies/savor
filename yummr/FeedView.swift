//
//  FeedView.swift
//  yummr
//
//  Created by kuba woahz on 6/28/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseFirestoreSwift

struct FeedView: View {
    @EnvironmentObject var auth: AuthService
    @State private var posts: [Post] = []
    @State private var allowedAuthorIDs: Set<String> = []
    @State private var postsListener: ListenerRegistration?
    @State private var friendsListener: ListenerRegistration?
    @State private var showNotifications = false
    @State private var isRefreshing = false

    private let db = Firestore.firestore()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(posts) { post in
                        NavigationLink(destination: PostDetailView(post: post)) {
                            PostCard(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("The Feed")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNotifications = true
                    } label: {
                        Image(systemName: "bell")
                    }
                }
            }
            .refreshable { refreshFeed() }
            .onAppear {
                guard let uid = auth.currentUser?.uid else { return }
                listenForFriends(uid: uid)
                listenForPosts()
            }
            .onDisappear {
                postsListener?.remove()
                friendsListener?.remove()
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsView()
            }
        }
    }

    private func listenForFriends(uid: String) {
        friendsListener?.remove()
        friendsListener = FriendService.shared.observeFriendIDs(for: uid) { ids in
            DispatchQueue.main.async {
                var combined = Set(ids)
                combined.insert(uid)
                allowedAuthorIDs = combined
                refreshFeed()
            }
        }
    }

    private func listenForPosts() {
        postsListener?.remove()
        postsListener = db.collection("posts")
            .order(by: "timestamp", descending: true)
            .limit(to: 100)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let fetched = docs.compactMap { try? $0.data(as: Post.self) }
                DispatchQueue.main.async {
                    applyFeedFilter(on: fetched)
                }
            }
    }

    private func refreshFeed() {
        guard !allowedAuthorIDs.isEmpty else { return }
        isRefreshing = true
        db.collection("posts")
            .order(by: "timestamp", descending: true)
            .limit(to: 100)
            .getDocuments { snapshot, _ in
                let fetched = snapshot?.documents.compactMap { try? $0.data(as: Post.self) } ?? []
                DispatchQueue.main.async {
                    applyFeedFilter(on: fetched)
                    isRefreshing = false
                }
            }
    }

    private func applyFeedFilter(on fetched: [Post]) {
        let filtered = fetched
            .filter { allowedAuthorIDs.contains($0.authorID) }
            .sorted { $0.timestamp > $1.timestamp }
        posts = filtered
    }
}
