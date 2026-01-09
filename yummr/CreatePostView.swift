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
    @State private var recipe: AttributedString = AttributedString()
    @State private var cookTime = ""
    @State private var calorieEstimate = ""
    @State private var starRating: Double = 0
    @State private var isFavorite = false
    @State private var ingredients: [String] = []
    @State private var ingredientDraft = ""
    @State private var selectedImages: [UIImage] = []
    @State private var aiReferenceImages: [UIImage] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var uploadProgress: [Double] = []
    @State private var isUploading = false
    @State private var uploadSuccess = false
    @State private var errorMessage: String?

    @State private var showCameraPicker = false
    @State private var cameraUnavailableAlert = false
    @State private var capturedImage: UIImage?

    @State private var taggingMode: TaggingMode = .post
    @State private var selectedImageIndex = 0
    @State private var selectedLocation: TagLocation = .center
    @State private var tagSearchText = ""
    @State private var tagSearchResults: [AppUser] = []
    @State private var pendingTags: [PendingTag] = []
    @State private var audioTranscript: String = ""
    @State private var aiNotes: [String] = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    Group {
                        TextField("Title", text: $title)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("Description", text: $description, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        photoActionButtons

                        TextField("Cook time (e.g. 45 minutes)", text: $cookTime)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    ingredientsSection

                    TextField("Calories (estimated)", text: $calorieEstimate)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recipe Instructions")
                            .font(.headline)
                        ZStack(alignment: .topLeading) {
                            if recipe.characters.isEmpty {
                                Text("Write step-by-step instructions...")
                                    .foregroundColor(.secondary)
                                    .padding(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 0))
                            }
                            RichTextEditor(text: $recipe)
                                .frame(minHeight: 120)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3))
                                )
                        }
                    }

                    NavigationLink {
                        AIDraftWorkshopView(
                            title: $title,
                            description: $description,
                            recipe: $recipe,
                            ingredients: $ingredients,
                            selectedImages: $selectedImages,
                            aiReferenceImages: $aiReferenceImages,
                            audioTranscript: $audioTranscript,
                            cookTime: $cookTime,
                            calorieEstimate: $calorieEstimate,
                            aiNotes: $aiNotes
                        )
                    } label: {
                        Label("Auto Log with AI", systemImage: "wand.and.stars")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(Color.accentColor)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    ratingSection
                    taggingSection

                    Button("Post") {
                        postContent()
                    }
                    .disabled(isUploading || selectedImages.isEmpty || title.isEmpty)
                    .buttonStyle(.borderedProminent)

                    if !aiNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI Notes")
                                .appTextStyle(.headline, weight: .semibold)
                            ForEach(aiNotes, id: \.self) { note in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(.accentColor)
                                        .font(.footnote)
                                    Text(note)
                                        .appTextStyle(.body)
                                }
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                    }

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
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
        .sheet(isPresented: $showCameraPicker) {
            ImagePicker(image: $capturedImage, sourceType: .camera)
        }
        .alert("Camera unavailable", isPresented: $cameraUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This device can't capture photos right now. Try selecting images from your library instead.")
        }
        .onChange(of: selectedPhotos) { items in
            Task {
                var newImages = selectedImages
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        newImages.append(uiImage)
                    }
                }
                selectedImages = newImages
                selectedPhotos = []
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

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your rating")
                .font(.headline)

            StarRatingInput(rating: $starRating)

            Toggle("Mark as favorite", isOn: $isFavorite)
        }
    }

    private struct StarRatingInput: View {
        @Binding var rating: Double

        var body: some View {
            GeometryReader { geometry in
                let width = geometry.size.width
                let stepWidth = width / 5
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { index in
                        Image(systemName: symbol(for: index))
                            .foregroundColor(.yellow)
                            .font(.system(size: 20, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let clamped = min(max(0, value.location.x), width)
                            let raw = clamped / stepWidth
                            let halfSteps = (raw * 2).rounded() / 2
                            rating = min(5, max(0, halfSteps))
                        }
                )
            }
            .frame(height: 28)
        }

        private func symbol(for index: Int) -> String {
            let threshold = rating - Double(index)
            if threshold >= 1 { return "star.fill" }
            if threshold >= 0.5 { return "star.leadinghalf.filled" }
            return "star"
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

    private var photoActionButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Photos")
                .font(.headline)

            HStack(spacing: 12) {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 5,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 28, weight: .semibold))
                        Text("Gallery")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(16)
                }
                .buttonStyle(.plain)

                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCameraPicker = true
                    } else {
                        cameraUnavailableAlert = true
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "camera")
                            .font(.system(size: 28, weight: .semibold))
                        Text("Camera")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(16)
                }
                .buttonStyle(.plain)
            }

            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(selectedImages.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 160, height: 160)
                                    .clipped()
                                    .cornerRadius(12)

                                Button {
                                    selectedImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.6).clipShape(Circle()))
                                }
                                .padding(6)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
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

    private func sanitizedInstructionSteps(from text: String) -> [String] {
        let rawSteps = text.components(separatedBy: CharacterSet.newlines)
        let cleaned = rawSteps.map { step -> String in
            let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            if let match = trimmed.range(of: "^\\d+(?:\\.\\d+)*[\\).\\-]*", options: .regularExpression) {
                let remainder = trimmed.replacingCharacters(in: match, with: "")
                return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return trimmed
        }.filter { !$0.isEmpty }
        return cleaned
    }

    private func postContent() {
        guard !selectedImages.isEmpty else {
            errorMessage = "Please select at least one image."
            return
        }

        isUploading = true
        uploadProgress = Array(repeating: 0, count: selectedImages.count)

        let uniqueTaggedIDs = Array(Set(pendingTags.map { $0.user.id ?? "" }.filter { !$0.isEmpty }))

        let photoTags: [Post.PhotoTag] = pendingTags.compactMap { (tag) -> Post.PhotoTag? in
            guard let userID = tag.user.id else { return nil }
            guard let index  = tag.imageIndex else { return nil }

            // If Coordinates is a struct with x/y:
            let coords = tag.location?.coordinates ?? (0.5, 0.5)
            return Post.PhotoTag(
                userID: userID,
                imageIndex: index,
                x: coords.0,
                y: coords.1,
                label: tag.user.displayName
            )
        }

        var extras: [String: String] = [:]
        if !ingredients.isEmpty {
            extras["ingredients"] = ingredients.joined(separator: "\n")
        }
        let trimmedTranscript = audioTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTranscript.isEmpty {
            extras["aiVoiceTranscript"] = trimmedTranscript
        }

        let trimmedCalories = calorieEstimate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCalories.isEmpty {
            extras["calorieEstimate"] = trimmedCalories
        }

        if !aiNotes.isEmpty {
            extras["aiNotes"] = aiNotes.joined(separator: "\n")
        }

        let roundedRating = (starRating * 10).rounded() / 10
        if roundedRating > 0 {
            extras["starRating"] = String(format: "%.1f", roundedRating)
        }

        if isFavorite {
            extras["isFavorite"] = "true"
        }

        let recipeText = recipe.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedSteps = sanitizedInstructionSteps(from: recipeText)
        let recipePayload = sanitizedSteps.isEmpty ? nil : sanitizedSteps.joined(separator: "\n")

        PostService.shared.uploadPost(
            title: title,
            description: description,
            recipe: recipePayload,
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
                recipe = AttributedString()
                cookTime = ""
                ingredients = []
                pendingTags = []
                selectedImages = []
                selectedPhotos = []
                audioTranscript = ""
                aiReferenceImages = []
                calorieEstimate = ""
                starRating = 0
                isFavorite = false
                aiNotes = []
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}
