import SwiftUI
import UIKit

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func store(image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url.absoluteString as NSString)
    }
}

struct CachedWebImage<Placeholder: View>: View {
    private let url: URL?
    private let placeholder: Placeholder

    @State private var uiImage: UIImage?
    @State private var isLoading = false

    init(url: URL?, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let uiImage = uiImage {
                Image(uiImage: uiImage)
                    .resizable()
            } else {
                placeholder
                    .onAppear(perform: load)
            }
        }
    }

    private func load() {
        guard !isLoading else { return }
        guard let url = url else { return }
        if let cached = ImageCache.shared.image(for: url) {
            uiImage = cached
            return
        }
        isLoading = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    isLoading = false
                }
                return
            }
            ImageCache.shared.store(image: image, for: url)
            DispatchQueue.main.async {
                uiImage = image
                isLoading = false
            }
        }.resume()
    }
}
