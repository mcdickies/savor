import SwiftUI
import FirebaseFirestore

struct SavedCollectionsView: View {
    @EnvironmentObject var auth: AuthService
    @State private var listener: ListenerRegistration?
    @State private var posts: [Post] = []

    private let grid = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                if posts.isEmpty {
                    Spacer()
                    Text("No saved posts yet.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: grid, spacing: 16) {
                            ForEach(posts) { post in
                                NavigationLink(destination: PostDetailView(post: post)) {
                                    CachedWebImage(url: URL(string: post.imageURLs.first ?? "")) {
                                        ProgressView()
                                    }
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 160)
                                    .clipped()
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Saves")
            .onAppear(perform: startListening)
            .onDisappear(perform: stopListening)
        }
    }

    private func startListening() {
        guard let uid = auth.currentUser?.uid else { return }
        listener?.remove()
        SavedService.shared.ensureDefaultCollection(for: uid)
        listener = SavedService.shared.observeCollection(for: uid, collectionID: "all") { collection in
            DispatchQueue.main.async {
                if let collection {
                    loadPosts(for: collection)
                } else {
                    posts = []
                }
            }
        }
    }

    private func stopListening() {
        listener?.remove()
        listener = nil
    }

    private func loadPosts(for collection: AppUser.SavedCollection) {
        guard !collection.postIDs.isEmpty else {
            posts = []
            return
        }

        let unique = Array(Set(collection.postIDs))
        var loaded: [Post] = []
        let group = DispatchGroup()
        for chunk in unique.chunked(into: 10) {
            group.enter()
            Firestore.firestore()
                .collection("posts")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments { snapshot, _ in
                    if let docs = snapshot?.documents {
                        let postsChunk = docs.compactMap { try? $0.data(as: Post.self) }
                        loaded.append(contentsOf: postsChunk)
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            posts = loaded.sorted { $0.timestamp > $1.timestamp }
        }
    }

}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            result.append(Array(self[index..<end]))
            index = end
        }
        return result
    }
}
