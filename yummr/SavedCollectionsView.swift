import SwiftUI
import FirebaseFirestore

struct SavedCollectionsView: View {
    @EnvironmentObject var auth: AuthService
    @State private var collections: [AppUser.SavedCollection] = []
    @State private var selectedCollectionID: String = "all"
    @State private var listener: ListenerRegistration?
    @State private var posts: [Post] = []
    @State private var showNewCollectionPrompt = false
    @State private var newCollectionName = ""

    private let grid = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(collections) { collection in
                            Button {
                                selectedCollectionID = collection.resolvedID
                                loadPosts(for: collection)
                            } label: {
                                Text(collection.title)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedCollectionID == collection.resolvedID ? Color.accentColor.opacity(0.2) : Color(UIColor.systemGray6))
                                    .cornerRadius(16)
                            }
                        }

                        Button {
                            showNewCollectionPrompt = true
                        } label: {
                            Image(systemName: "plus")
                                .padding()
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal)
                }

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
            .alert("New Collection", isPresented: $showNewCollectionPrompt) {
                TextField("Title", text: $newCollectionName)
                Button("Create") { createCollection() }
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            }
        }
    }

    private func startListening() {
        guard let uid = auth.currentUser?.uid else { return }
        listener?.remove()
        listener = SavedService.shared.observeCollections(for: uid) { collections in
            DispatchQueue.main.async {
                self.collections = collections
                if !collections.contains(where: { $0.resolvedID == selectedCollectionID }) {
                    selectedCollectionID = collections.first?.resolvedID ?? "all"
                }
                if let selected = collections.first(where: { $0.resolvedID == selectedCollectionID }) {
                    loadPosts(for: selected)
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

    private func createCollection() {
        guard let uid = auth.currentUser?.uid else { return }
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        SavedService.shared.createCollection(uid: uid, title: trimmed)
        newCollectionName = ""
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
