import SwiftUI

/// In-memory store of already-decoded images, keyed by URL.
///
/// `URLCache` alone is not enough: it spares the network round trip, but `AsyncImage` still starts
/// every appearance in its `.empty` phase and decodes again — which is why leaving and re-entering
/// a project made each icon blink out and reload.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 300
        return c
    }()

    private init() {}

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func insert(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// Drop-in replacement for `AsyncImage` that keeps decoded images around.
///
/// Once an image has been seen, later appearances render it on the first frame — no placeholder
/// flash, no refetch.
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        // Read the cache synchronously so an already-seen image never flashes a placeholder
        // while `.task` spins up.
        .onAppear { image = image ?? ImageCache.shared.image(for: url) }
        .task(id: url) { await load() }
    }

    private func load() async {
        if let cached = ImageCache.shared.image(for: url) {
            image = cached
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = UIImage(data: data)
        else { return }

        ImageCache.shared.insert(decoded, for: url)
        image = decoded
    }
}
