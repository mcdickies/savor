
import Foundation
import FirebaseStorage
import UIKit
//push
class StorageService {
    static let shared = StorageService()

    private let storageRef = Storage.storage().reference()

    /// Uploads a UIImage to Firebase Storage and returns the download URL as a string.
    func uploadImage(_ image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        // Compress image to JPEG
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "StorageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data."])))
            return
        }

        // Create a unique file name
        let imageID = UUID().uuidString
        let imageRef = storageRef.child("images/\(imageID).jpg")

        // Upload data
        imageRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            // Fetch download URL
            imageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error))
                } else if let downloadURL = url {
                    completion(.success(downloadURL.absoluteString))
                } else {
                    completion(.failure(NSError(domain: "StorageService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Download URL is nil."])))
                }
            }
        }
    }
}
