

import SwiftUI
import PhotosUI

struct CreatePostView: View {
    @State private var title = ""
    @State private var description = ""
    @State private var selectedImage: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
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
                    selection: $selectedPhoto,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                            .cornerRadius(10)
                    } else {
                        Text("Select an Image")
                            .foregroundColor(.blue)
                    }
                }
                .onChange(of: selectedPhoto) {
                    Task {
                        if let data = try? await selectedPhoto?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            selectedImage = uiImage
                        }
                    }
                }


                if isUploading {
                    ProgressView("Uploading...")
                }

                Button("Post") {
                    guard let image = selectedImage else {
                        errorMessage = "Please select an image."
                        return
                    }

                    isUploading = true
                    PostService.shared.uploadPost(title: title, description: description, image: image) { result in
                        isUploading = false
                        switch result {
                        case .success:
                            uploadSuccess = true
                            title = ""
                            description = ""
                            selectedImage = nil
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
        }
    }
}
