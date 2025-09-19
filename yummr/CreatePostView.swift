import SwiftUI
import PhotosUI
import UIKit

struct CreatePostView: View {
    enum TaggingMode: String, CaseIterable, Identifiable {
        case post = "Entire Post"
        case photo = "Specific Photo"

        var id: String { rawValue }
    }

    enum TagLocation: String, CaseIterable, Identifiable {
        case center = "Center"
        case topLeft = "Top Left"
        case topRight = "Top Right"
        case bottomLeft = "Bottom Left"
        case bottomRight = "Bottom Right"

        var id: String { rawValue }

        var coordinates: (x: Double, y: Double) {
            switch self {
            case .center: return (0.5, 0.5)
            case .topLeft: return (0.2, 0.2)
            case .topRight: return (0.8, 0.2)
            case .bottomLeft: return (0.2, 0.8)
            case .bottomRight: return (0.8, 0.8)
            }
        }
    }

    struct PendingTag: Identifiable {
        let id = UUID()
        let user: AppUser
        var imageIndex: Int?
        var location: TagLocation?
    }

    @State private var title = ""
    @State private var description = ""
    @State private var recipe = ""
    @State private var cookTime = ""
    @State private var ingredients: [String] = []
    @State private var ingredientDraft = ""
    @State private var selectedImages: [UIImage] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var uploadProgress: [Double] = []
    @State private var editMode: EditMode = .inactive
    @State private var isUploading = false
    @State private var uploadSuccess = false
    @State private var errorMessage: String?

    @State private var showCameraPicker = false
    @State private var capturedImage: UIImage?

    @State private var taggingMode: TaggingMode = .post
    @State private var selectedImageIndex = 0
    @State private var selectedLocation: TagLocation = .center
    @State private var tagSearchText = ""
    @State private var tagSearchResults: [AppUser] = []
    @State private var pendingTags: [PendingTag] = []
    @State private var audioTranscript: String = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    NavigationLink {
                        AIDraftWorkshopView(
                            title: $title,
                            description: $description,
                            recipe: $recipe,
                            selectedImages: $selectedImages,
                            audioTranscript: $audioTranscript
                        )
                    } label: {
                        Label("AI Draft", systemImage: "wand.and.stars")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(Color.accentColor)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    Group {
                        TextField("Title", text: $title)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("Description", text: $description, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recipe Instructions")
                                .font(.headline)
                            ZStack(alignment: .topLeading) {
                                if recipe.isEmpty {
                                    Text("Write step-by-step instructions...")
                                        .foregroundColor(.gray)
                                        .padding(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 0))
                                }
                                TextEditor(text: $recipe)
                                    .frame(minHeight: 120)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.3))
                                    )
                            }
                        }

                        TextField("Cook time (e.g. 45 minutes)", text: $cookTime)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    ingredientsSection
                    mediaSelectionSection
                    taggingSection

                    Button("Post") {
                        postContent()
                    }
                    .disabled(isUploading || selectedImages.isEmpty || title.isEmpty)
                    .buttonStyle(.borderedProminent)

                    if let error = errorMessage {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    if uploadSuccess {
                        Text("Post uploaded successfully!")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                .padding()
            }
            .navigationTitle("Create Post")
            .toolbar { EditButton() }
        }
        .sheet(isPresented: $showCameraPicker) {
            ImagePicker(image: $capturedImage, sourceType: .camera)
        }
        .onChange(of: selectedPhotos) { items in
            Task {
                selectedImages = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        selectedImages.append(uiImage)
                    }
                }
            }
        }
        .onChange(of: capturedImage) { image in
            if let image = image {
                selectedImages.append(image)
                capturedImage = nil
            }
        }
        .onChange(of: selectedImages) { images in
            if selectedImageIndex >= images.count {
                selectedImageIndex = max(0, images.count - 1)
            }
        }
        .onChange(of: tagSearchText) { newValue in
            UserService.shared.searchUsers(matching: newValue) { users in
                DispatchQueue.main.async {
                    tagSearchResults = users
                }
            }
        }
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ingredients & Keywords")
                .font(.headline)
            HStack {
                TextField("Add ingredient or keyword", text: $ingredientDraft)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Add") {
                    addIngredient()
                }
                .disabled(ingredientDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !ingredients.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(ingredients, id: \.self) { ingredient in
                        HStack {
                            Text(ingredient)
                                .font(.footnote)
                            Button(action: { removeIngredient(ingredient) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(12)
                    }
                }
            }
        }
    }

    private var mediaSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photos")
                .font(.headline)

            HStack {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 5,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text("Select Images")
                        .foregroundColor(.blue)
                }

                Button {
                    showCameraPicker = true
                } label: {
                    Label("Capture Photo", systemImage: "camera")
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            }

            if !selectedImages.isEmpty {
                List {
                    ForEach(selectedImages.indices, id: \.self) { index in
                        VStack {
                            Image(uiImage: selectedImages[index])
                                .resizable()
                                .scaledToFit()
                                .frame(height: 200)
                                .cornerRadius(10)
                            if isUploading && uploadProgress.indices.contains(index) {
                                ProgressView(value: uploadProgress[index])
                            }
                        }
                    }
                    .onDelete { offsets in
                        selectedImages.remove(atOffsets: offsets)
                    }
                    .onMove { indices, newOffset in
                        selectedImages.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .frame(height: 250)
                .environment(\.editMode, $editMode)
            }
        }
    }

    private var taggingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tag Users")
                .font(.headline)

            Picker("Tagging Mode", selection: $taggingMode) {
                ForEach(TaggingMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if taggingMode == .photo && !selectedImages.isEmpty {
                Picker("Photo", selection: $selectedImageIndex) {
                    ForEach(selectedImages.indices, id: \.self) { index in
                        Text("Photo #\(index + 1)").tag(index)
                    }
                }
                .pickerStyle(.menu)

                Picker("Location", selection: $selectedLocation) {
                    ForEach(TagLocation.allCases) { location in
                        Text(location.rawValue).tag(location)
                    }
                }
                .pickerStyle(.menu)
            }

            TextField("Search users to tag", text: $tagSearchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            if !tagSearchResults.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tagSearchResults, id: \.handle) { user in
                        Button {
                            addTag(for: user)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(user.displayName)
                                    Text("@\(user.handle)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Text("Tag")
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                    }
                }
            }

            if !pendingTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tagged")
                        .font(.subheadline)
                    ForEach(pendingTags) { tag in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tag.user.displayName)
                                Text("@\(tag.user.handle)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                if let index = tag.imageIndex {
                                    Text("Photo #\(index + 1) · \(tag.location?.rawValue ?? "Custom")")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Entire post")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                removeTag(tag)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .padding(8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private func addIngredient() {
        let trimmed = ingredientDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ingredients.append(trimmed)
        ingredientDraft = ""
    }

    private func removeIngredient(_ ingredient: String) {
        ingredients.removeAll { $0 == ingredient }
    }

    private func addTag(for user: AppUser) {
        if taggingMode == .photo && selectedImages.isEmpty {
            return
        }
        let location = taggingMode == .photo ? selectedLocation : nil
        let imageIndex = taggingMode == .photo ? selectedImageIndex : nil
        let newTag = PendingTag(user: user, imageIndex: imageIndex, location: location)
        pendingTags.append(newTag)
        tagSearchText = ""
        tagSearchResults = []
    }

    private func removeTag(_ tag: PendingTag) {
        pendingTags.removeAll { $0.id == tag.id }
    }

    private func postContent() {
        guard !selectedImages.isEmpty else {
            errorMessage = "Please select at least one image."
            return
        }

        isUploading = true
        uploadProgress = Array(repeating: 0, count: selectedImages.count)

        let uniqueTaggedIDs = Array(Set(pendingTags.map { $0.user.id ?? "" }.filter { !$0.isEmpty }))

        let photoTags: [Post.PhotoTag] = pendingTags.compactMap { tag in
            guard let userID = tag.user.id else { return nil }
            guard let index = tag.imageIndex, tag.location != nil else { return nil }
            let coordinates = tag.location?.coordinates ?? (0.5, 0.5)
            return Post.PhotoTag(userID: userID,
                                 imageIndex: index,
                                 x: coordinates.x,
                                 y: coordinates.y,
                                 label: tag.user.displayName)
        }

        var extras: [String: String] = [:]
        if !ingredients.isEmpty {
            extras["ingredients"] = ingredients.joined(separator: ", ")
        }
        let trimmedTranscript = audioTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTranscript.isEmpty {
            extras["aiVoiceTranscript"] = trimmedTranscript
        }

        PostService.shared.uploadPost(
            title: title,
            description: description,
            recipe: recipe.isEmpty ? nil : recipe,
            cookTime: cookTime.isEmpty ? nil : cookTime,
            taggedUserIDs: uniqueTaggedIDs,
            photoTags: photoTags,
            extraFields: extras,
            images: selectedImages,
            progressHandler: { index, progress in
                DispatchQueue.main.async {
                    if uploadProgress.indices.contains(index) {
                        uploadProgress[index] = progress
                    }
                }
            }
        ) { result in
            isUploading = false
            switch result {
            case .success:
                uploadSuccess = true
                title = ""
                description = ""
                recipe = ""
                cookTime = ""
                ingredients = []
                pendingTags = []
                selectedImages = []
                selectedPhotos = []
                audioTranscript = ""
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}
