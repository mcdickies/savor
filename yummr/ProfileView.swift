import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore
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
    @State private var showSettings = false
    @State private var followerCount: Int = 0
    @State private var followingCount: Int = 0
    @State private var activeFriendList: FriendListView.Mode?
    @State private var isFollowingProfile = false
    @State private var isProcessingFollowAction = false
    @State private var selectedPostID: String?
    @State private var isShowingUserFeed = false

    private let db = Firestore.firestore()
    @State private var friendListener: ListenerRegistration?
    @State private var profileListener: ListenerRegistration?

    private var resolvedUserID: String? {
        let candidate = userID ?? auth.currentUser?.uid
        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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
                    profileSummaryCard
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

                    if selectedTab == .posts && !pinnedFavoritePosts.isEmpty {
                        favoriteRecipesSection
                    }

                    Picker("Profile Content", selection: $selectedTab) {
                        ForEach(ProfileTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    profilePostGrid
                }
                .padding(.bottom, 24)
            }
            .navigationTitle(profileUser?.displayName ?? "Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isCurrentUser {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                        }
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
            startFriendListener()
            refreshFriendshipState()
        }
        .onDisappear(perform: stopListeners)
        .onChange(of: userID) { _ in
            loadProfileData()
            loadPosts()
            loadTaggedPosts()
            refreshFriendshipState()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedProfileImage)
                .onDisappear { uploadProfileImage() }
        }
        .sheet(isPresented: $showBannerPicker) {
            ImagePicker(image: $selectedBannerImage)
                .onDisappear { uploadBannerImage() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(auth)
        }
        .sheet(item: $activeFriendList) { mode in
            if let userID = resolvedUserID {
                FriendListView(userID: userID, mode: mode)
            } else {
                NavigationView {
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("User information is unavailable.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .navigationTitle(mode.title)
                }
            }
        }
    }

    private var currentPosts: [Post] {
        switch selectedTab {
        case .posts: return userPosts
        case .tagged: return taggedPosts
        }
    }

    private var pinnedFavoritePosts: [Post] {
        userPosts.filter { $0.isFavorited }
    }

    private var bannerSection: some View {
        ZStack {
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
        }
    }

    private var profileSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let profileURL = profileImageURL {
                            CachedWebImage(url: profileURL) {
                                Circle().fill(Color.gray.opacity(0.3))
                            }
                            .scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())

                    if isCurrentUser {
                        Button(action: { showImagePicker = true }) {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundColor(.accentColor)
                                .background(Color.white.clipShape(Circle()))
                        }
                        .offset(x: 4, y: 4)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(profileUser?.displayName ?? "New Chef")
                        .font(.headline)
                    if let handle = profileUser?.handle, !handle.isEmpty {
                        Text("@\(handle)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if isCurrentUser {
                    Button("Edit Bio") { isEditingBio = true }
                        .font(.caption)
                } else {
                    followActionButton
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if isEditingBio {
                    TextField("Enter bio", text: $bio, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    HStack(spacing: 12) {
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
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Button {
                    activeFriendList = .followers
                } label: {
                    VStack {
                        Text("Followers")
                            .font(.caption)
                            .foregroundColor(.primary)
                        Text("\(followerCount)")
                            .bold()
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(resolvedUserID == nil)

                Button {
                    activeFriendList = .following
                } label: {
                    VStack {
                        Text("Following")
                            .font(.caption)
                            .foregroundColor(.primary)
                        Text("\(followingCount)")
                            .bold()
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(resolvedUserID == nil)

                VStack {
                    Text("Posts")
                        .font(.caption)
                    Text("\(userPosts.count)")
                        .bold()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .padding(.horizontal)
    }

    private var profilePostGrid: some View {
        ZStack {
            Color.white
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
                ForEach(currentPosts) { post in
                    Button {
                        selectedPostID = post.stableIdentifier
                        isShowingUserFeed = true
                    } label: {
                        GeometryReader { geometry in
                            CachedWebImage(url: URL(string: post.imageURLs.first ?? "")) {
                                Color.gray.opacity(0.2)
                            }
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.width)
                            .clipped()
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
                }
            }

            userFeedNavigationLink
                .hidden()
        }
        .padding(.horizontal, 1)
    }

    private var favoriteRecipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Favorite Recipes")
                    .font(.headline)
                Spacer()
                Text("Pinned")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(pinnedFavoritePosts) { post in
                        NavigationLink(destination: PostDetailView(post: post)) {
                            CachedWebImage(url: URL(string: post.imageURLs.first ?? "")) {
                                Color.gray.opacity(0.2)
                            }
                            .frame(width: 140, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal)
    }

    private var followActionButton: some View {
        Button {
            guard !isProcessingFollowAction else { return }
            if isFollowingProfile {
                unfollowProfile()
            } else {
                followProfile()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isFollowingProfile ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus")
                Text(isFollowingProfile ? "Unfollow" : "Follow")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(isProcessingFollowAction || resolvedUserID == nil)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var userFeedNavigationLink: some View {
        if let userID = resolvedUserID {
            NavigationLink(
                destination: UserPostsFeedView(
                    authorID: userID,
                    authorName: profileUser?.displayName,
                    initialPostID: selectedPostID
                ),
                isActive: Binding(
                    get: { isShowingUserFeed },
                    set: { newValue in
                        if !newValue {
                            selectedPostID = nil
                        }
                        isShowingUserFeed = newValue
                    }
                )
            ) {
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }

    private func loadProfileData() {
        guard let uid = resolvedUserID else { return }
        profileListener?.remove()
        profileListener = db.collection("users").document(uid)
            .addSnapshotListener { snapshot, _ in
                if let user = try? snapshot?.data(as: AppUser.self) {
                    DispatchQueue.main.async {
                        self.profileUser = user
                        self.bio = user.bio ?? ""
                        let storedFollowers = user.followerCount ?? 0
                        let storedFollowing = user.followingCount ?? 0
                        self.followerCount = max(self.followerCount, storedFollowers)
                        self.followingCount = max(self.followingCount, storedFollowing)
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

    private func refreshFriendshipState() {
        guard !isCurrentUser, let uid = resolvedUserID else { return }
        FriendService.shared.isFriends(with: uid) { isFriend in
            DispatchQueue.main.async {
                self.isFollowingProfile = isFriend
            }
        }
    }

    private func updateBio() {
        guard let uid = resolvedUserID else { return }
        db.collection("users").document(uid).setData(["bio": bio], merge: true)
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
                        db.collection("users").document(uid).setData(["profileImageURL": url.absoluteString], merge: true)
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
                        db.collection("users").document(uid).setData(["bannerImageURL": url.absoluteString], merge: true)
                    }
                }
            }
        }
    }

    private func startFriendListener() {
        guard let uid = resolvedUserID else { return }
        friendListener?.remove()
        friendListener = FriendService.shared.observeFriendIDs(for: uid) { ids in
            DispatchQueue.main.async {
                self.followerCount = ids.count
                self.followingCount = ids.count
            }
        }
    }

    private func stopListeners() {
        friendListener?.remove()
        friendListener = nil
        profileListener?.remove()
        profileListener = nil
    }

    private func followProfile() {
        guard let uid = resolvedUserID else { return }
        isProcessingFollowAction = true
        FriendService.shared.createFriendship(with: uid) { error in
            DispatchQueue.main.async {
                self.isProcessingFollowAction = false
                if error == nil {
                    self.isFollowingProfile = true
                    self.loadProfileData()
                }
            }
        }
    }

    private func unfollowProfile() {
        guard let uid = resolvedUserID else { return }
        isProcessingFollowAction = true
        FriendService.shared.removeFriend(uid) { error in
            DispatchQueue.main.async {
                self.isProcessingFollowAction = false
                if error == nil {
                    self.isFollowingProfile = false
                    self.loadProfileData()
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

private struct FriendListView: View {
    enum Mode: String, Identifiable {
        case followers
        case following

        var id: String { rawValue }

        var title: String {
            switch self {
            case .followers: return "Followers"
            case .following: return "Following"
            }
        }

        var emptyMessage: String {
            switch self {
            case .followers: return "No followers yet."
            case .following: return "Not following anyone yet."
            }
        }
    }

    let userID: String
    let mode: Mode

    @State private var isLoading = true
    @State private var users: [AppUser] = []
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if users.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(mode.emptyMessage)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(users.indices, id: \.self) { index in
                            let user = users[index]
                            NavigationLink(destination: ProfileView(userID: user.id ?? "")) {
                                HStack(spacing: 12) {
                                    CachedWebImage(url: URL(string: user.profileImageURL ?? "")) {
                                        Circle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 44, height: 44)
                                    }
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(user.displayName)
                                            .font(.body)
                                        Text("@\(user.handle)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear(perform: loadUsers)
    }

    private func loadUsers() {
        guard !userID.isEmpty else {
            errorMessage = "User information is unavailable."
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        FriendService.shared.fetchFriendIDs(for: userID) { result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            case .success(let ids):
                guard !ids.isEmpty else {
                    DispatchQueue.main.async {
                        self.users = []
                        self.isLoading = false
                    }
                    return
                }

                UserService.shared.fetchUsers(withIDs: ids) { users in
                    let sorted = users.sorted {
                        ($0.displayName.lowercased(), $0.handle.lowercased())
                            < ($1.displayName.lowercased(), $1.handle.lowercased())
                    }
                    self.users = sorted
                    self.isLoading = false
                }
            }
        }
    }
}
