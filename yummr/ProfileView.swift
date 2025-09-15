import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct ProfileView: View {
    @EnvironmentObject var auth: AuthService
    @State private var bio: String = ""
    @State private var selectedImage: UIImage? = nil
    @State private var profileImageURL: URL? = nil
    @State private var showImagePicker = false
    @State private var showSettings = false
    @State private var isEditing = false
    @State private var userPosts: [Post] = []

    private let db = Firestore.firestore()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .center, spacing: 16) {
                    // Profile Picture
                    ZStack(alignment: .bottomTrailing) {
                        if let url = profileImageURL {
                            AsyncImage(url: url) { image in
                                image.resizable()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 100, height: 100)
                        }

                        Button(action: {
                            showImagePicker = true
                        }) {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .offset(x: 5, y: 5)
                    }

                    // Name and Bio
                    Text(auth.currentUser?.displayName ?? auth.currentUser?.email ?? "Username")
                        .font(.title2)
                        .bold()

                    if isEditing {
                        TextField("Enter bio", text: $bio)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                        Button("Save") {
                            updateBio()
                            isEditing = false
                        }
                    } else {
                        Text(bio.isEmpty ? "No bio yet." : bio)
                            .italic()
                            .foregroundColor(.gray)
                        Button("Edit Bio") {
                            isEditing = true
                        }
                    }

                    // User's Posts Grid
                    Text("My Posts")
                        .font(.headline)
                        .padding(.top)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(userPosts) { post in
                            NavigationLink {
                                UserPostsFeedView(authorID: post.authorID, authorName: post.authorName)
                            } label: {
                                VStack {
                                    AsyncImage(url: URL(string: post.imageURL)) { phase in
                                        switch phase {
                                        case .empty:
                                            ProgressView()
                                        case .success(let image):
                                            image.resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(height: 100)
                                                .clipped()
                                                .cornerRadius(8)
                                        case .failure:
                                            Image(systemName: "photo")
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                    Text(post.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .onAppear {
            loadProfileData()
            loadUserPosts()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
                .onDisappear {
                    uploadProfileImage()
                }
        }
    }

    private func loadProfileData() {
        guard let uid = auth.currentUser?.uid else { return }

        db.collection("users").document(uid).getDocument { snapshot, error in
            if let data = snapshot?.data() {
                self.bio = data["bio"] as? String ?? ""
                if let urlString = data["profileImageURL"] as? String,
                   let url = URL(string: urlString) {
                    self.profileImageURL = url
                }
            }
        }
    }

    private func loadUserPosts() {
        guard let uid = auth.currentUser?.uid else { return }
        db.collection("posts")
            .whereField("authorID", isEqualTo: uid)
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                if let docs = snapshot?.documents {
                    self.userPosts = docs.compactMap { try? $0.data(as: Post.self) }
                }
            }
    }

    private func updateBio() {
        guard let uid = auth.currentUser?.uid else { return }
        db.collection("users").document(uid).updateData(["bio": bio])
    }

    private func uploadProfileImage() {
        guard let uid = auth.currentUser?.uid,
              let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.8) else { return }

        let storageRef = Storage.storage().reference().child("profileImages/\(uid).jpg")
        storageRef.putData(imageData, metadata: nil) { _, error in
            if error == nil {
                storageRef.downloadURL { url, _ in
                    if let url = url {
                        self.profileImageURL = url
                        db.collection("users").document(uid).updateData(["profileImageURL": url.absoluteString])
                    }
                }
            }
        }
    }
}

