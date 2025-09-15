import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseFirestoreSwift
import FirebaseStorage

struct ProfileView: View {
    enum ProfileTab: String, CaseIterable, Identifiable {
        case posts = "Posts"
        case tagged = "Tagged"

        var id: String { rawValue }
    }

    var userID: String? = nil

    @EnvironmentObject var auth: AuthService
    @State private var profileUser: AppUser?
    @State private var bio: String = ""
    @State private var profileImageURL: URL? = nil
    @State private var bannerImageURL: URL? = nil
    @State private var showImagePicker = false
    @State private var showBannerPicker = false
    @State private var isEditingBio = false
    @State private var userPosts: [Post] = []
    @State private var taggedPosts: [Post] = []
    @State private var selectedTab: ProfileTab = .posts

    @State private var selectedProfileImage: UIImage?
    @State private var selectedBannerImage: UIImage?

    private let db = Firestore.firestore()

    private var resolvedUserID: String? {
        userID ?? auth.currentUser?.uid
    }

    private var isCurrentUser: Bool {
        guard let resolved = resolvedUserID, let current = auth.currentUser?.uid else {
            return false
        }
        return resolved == current
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    bannerSection
                    headerSection
                    statsSection
                    if let topFoods = profileUser?.topFoods, !topFoods.isEmpty {
                        TagSection(title: "Top Foods", tags: topFoods)
                    }
                    if let healthMetrics = profileUser?.healthMetrics, !healthMetrics.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Health Metrics")
                                .font(.headline)
                            ForEach(healthMetrics.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                HStack {
                                    Text(key)
                                        .font(.subheadline)
                                    Spacer()
                                    Text(value)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    Picker("Profile Content", selection: $selectedTab) {
                        ForEach(ProfileTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(currentPosts) { post in
                            NavigationLink(destination: PostDetailView(post: post)) {
                                CachedWebImage(url: URL(string: post.imageURLs.first ?? "")) {
                                    ProgressView()
                                }
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 140)
                                .clipped()
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle(profileUser?.displayName ?? "Profile")
            .toolbar {
                if isCurrentUser {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showImagePicker = true }) {
                            Image(systemName: "pencil")
                        }
                    }
                }
            }
        }
        .onAppear {
            loadProfileData()
            loadPosts()
            loadTaggedPosts()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedProfileImage)
                .onDisappear { uploadProfileImage() }
        }
        .sheet(isPresented: $showBannerPicker) {
            ImagePicker(image: $selectedBannerImage)
                .onDisappear { uploadBannerImage() }
        }
    }

    private var currentPosts: [Post] {
        switch selectedTab {
        case .posts: return userPosts
        case .tagged: return taggedPosts
        }
    }

    private var bannerSection: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let bannerURL = bannerImageURL {
                    CachedWebImage(url: bannerURL) {
                        Color.gray.opacity(0.3)
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 160)
                    .clipped()
                } else {
                    Color(UIColor.systemGray5)
                        .frame(height: 160)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isCurrentUser {
                    Button(action: { showBannerPicker = true }) {
                        Image(systemName: "photo.on.rectangle")
                            .padding(8)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                            .foregroundColor(.white)
                            .padding()
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    if let profileURL = profileImageURL {
                        CachedWebImage(url: profileURL) {
                            Circle().fill(Color.gray)
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 4))
                    } else {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 100, height: 100)
                            .overlay(Circle().stroke(Color.white, lineWidth: 4))
                    }

                    if isCurrentUser {
                        Button(action: { showImagePicker = true }) {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundColor(.blue)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                        .offset(x: 10, y: 10)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(profileUser?.displayName ?? auth.currentUser?.displayName ?? "Username")
                        .font(.title2)
                        .bold()
                    Text("@\(profileUser?.handle ?? auth.currentUser?.email ?? "handle")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 12)
            }
            .padding([.leading, .bottom], 16)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditingBio {
                TextField("Enter bio", text: $bio, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                HStack {
                    Button("Save") {
                        updateBio()
                        isEditingBio = false
                    }
                    Button("Cancel") {
                        bio = profileUser?.bio ?? ""
                        isEditingBio = false
                    }
                }
                .font(.caption)
            } else {
                Text(bio.isEmpty ? "No bio yet." : bio)
                    .italic()
                    .foregroundColor(.gray)
                if isCurrentUser {
                    Button("Edit Bio") { isEditingBio = true }
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal)
    }

    private var statsSection: some View {
        HStack {
            VStack {
                Text("Followers")
                    .font(.caption)
                Text("\(profileUser?.followerCount ?? 0)")
                    .bold()
            }
            .frame(maxWidth: .infinity)
            VStack {
                Text("Following")
                    .font(.caption)
                Text("\(profileUser?.followingCount ?? 0)")
                    .bold()
            }
            .frame(maxWidth: .infinity)
            VStack {
                Text("Posts")
                    .font(.caption)
                Text("\(userPosts.count)")
                    .bold()
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private func loadProfileData() {
        guard let uid = resolvedUserID else { return }
        db.collection("users").document(uid).getDocument { snapshot, _ in
            if let user = try? snapshot?.data(as: AppUser.self) {
                DispatchQueue.main.async {
                    self.profileUser = user
                    self.bio = user.bio ?? ""
                    if let profileURL = user.profileImageURL, let url = URL(string: profileURL) {
                        self.profileImageURL = url
                    }
                    if let bannerURL = user.bannerImageURL, let url = URL(string: bannerURL) {
                        self.bannerImageURL = url
                    }
                }
            }
        }
    }

    private func loadPosts() {
        guard let uid = resolvedUserID else { return }
        db.collection("posts")
            .whereField("authorID", isEqualTo: uid)
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, _ in
                if let docs = snapshot?.documents {
                    DispatchQueue.main.async {
                        self.userPosts = docs.compactMap { try? $0.data(as: Post.self) }
                    }
                }
            }
    }

    private func loadTaggedPosts() {
        guard let uid = resolvedUserID else { return }
        PostService.shared.fetchTaggedPosts(for: uid) { posts in
            DispatchQueue.main.async {
                self.taggedPosts = posts.sorted { $0.timestamp > $1.timestamp }
            }
        }
    }

    private func updateBio() {
        guard let uid = resolvedUserID else { return }
        db.collection("users").document(uid).updateData(["bio": bio])
        if isCurrentUser {
            self.profileUser?.bio = bio
        }
    }

    private func uploadProfileImage() {
        guard let uid = resolvedUserID,
              let image = selectedProfileImage,
              let imageData = image.jpegData(compressionQuality: 0.8) else { return }

        let storageRef = Storage.storage().reference().child("profileImages/\(uid).jpg")
        storageRef.putData(imageData, metadata: nil) { _, error in
            if error == nil {
                storageRef.downloadURL { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.profileImageURL = url
                        }
                        db.collection("users").document(uid).updateData(["profileImageURL": url.absoluteString])
                    }
                }
            }
        }
    }

    private func uploadBannerImage() {
        guard let uid = resolvedUserID,
              let image = selectedBannerImage,
              let data = image.jpegData(compressionQuality: 0.8) else { return }

        let storageRef = Storage.storage().reference().child("bannerImages/\(uid).jpg")
        storageRef.putData(data, metadata: nil) { _, error in
            if error == nil {
                storageRef.downloadURL { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.bannerImageURL = url
                        }
                        db.collection("users").document(uid).updateData(["bannerImageURL": url.absoluteString])
                    }
                }
            }
        }
    }
}

private struct TagSection: View {
    let title: String
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.horizontal)
    }
}
