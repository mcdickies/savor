

import SwiftUI
import PhotosUI

struct CreatePostView: View {
    @State private var title = ""
    @State private var description = ""
    @State private var selectedImages: [UIImage] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var uploadProgress: [Double] = []
    @State private var editMode: EditMode = .inactive
    @State private var isUploading = false
    @State private var uploadSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("Title", text: $title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                TextField("Description", text: $description)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 5,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text("Select Images")
                        .foregroundColor(.blue)
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
                        .onMove { indices, newOffset in
                            selectedImages.move(fromOffsets: indices, toOffset: newOffset)
                        }
                    }
                    .frame(height: 250)
                    .environment(\.editMode, $editMode)
                }

                Button("Post") {
                    guard !selectedImages.isEmpty else {
                        errorMessage = "Please select at least one image."
                        return
                    }

                    isUploading = true
                    uploadProgress = Array(repeating: 0, count: selectedImages.count)
                    PostService.shared.uploadPost(title: title, description: description, images: selectedImages, progressHandler: { index, progress in
                        DispatchQueue.main.async {
                            if uploadProgress.indices.contains(index) {
                                uploadProgress[index] = progress
                            }
                        }
                    }) { result in
                        isUploading = false
                        switch result {
                        case .success:
                            uploadSuccess = true
                            title = ""
                            description = ""
                            selectedImages = []
                            selectedPhotos = []
                        case .failure(let error):
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(isUploading)
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

                Spacer()
            }
            .padding()
            .navigationTitle("Create Post")
            .toolbar { EditButton() }
        }
    }
}
