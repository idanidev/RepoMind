import CryptoKit
import Foundation
import SwiftUI

// MARK: - Repo icon store

/// Loads and caches repository icons.
///
/// Two things broke icons before this. A GitHub `download_url` for a file in a private repo
/// carries a query token that expires within minutes, so the icon loaded once and never again.
/// And a photo chosen from the library was stored as an absolute path inside the app container,
/// which iOS moves on every update, so the file looked lost after each TestFlight build. Now a
/// GitHub file is fetched with the account's token in a header, every download is kept on disk
/// under Caches, and a stale container path is resolved by file name.
@MainActor
final class RepoIconStore {
    static let shared = RepoIconStore()

    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private init() {}

    /// The image for a stored icon URL, from memory, disk, or the network — in that order.
    /// `tokenKey` is the Keychain key of the account that can read the repo, used only for
    /// GitHub's raw file host.
    func image(for url: URL, tokenKey: String?) async -> UIImage? {
        let key = Self.canonical(url)
        if let cached = ImageCache.shared.image(for: key) { return cached }
        if let running = inFlight[key] { return await running.value }

        let task = Task<UIImage?, Never> { await self.load(key, tokenKey: tokenKey) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            ImageCache.shared.insert(image, for: key)
        }
        return image
    }

    private func load(_ url: URL, tokenKey: String?) async -> UIImage? {
        if url.isFileURL {
            guard let resolved = Self.resolve(fileURL: url) else { return nil }
            return UIImage(contentsOfFile: resolved.path)
        }
        if let data = Self.diskCached(url), let image = UIImage(data: data) {
            return image
        }
        var token: String?
        if Self.needsToken(url), let tokenKey {
            token = try? await KeychainManager.shared.retrieveToken(for: tokenKey)
        }
        guard let data = try? await GitHubService.shared.download(url, token: token),
              let image = UIImage(data: data)
        else { return nil }
        Self.diskStore(data, for: url)
        return image
    }

    // MARK: URLs

    /// A GitHub raw URL without its throwaway `token` query: the stable identity of the file.
    static func canonical(_ url: URL) -> URL {
        guard needsToken(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.queryItems = nil
        return components.url ?? url
    }

    /// What to store in `ProjectRepo.logoURL` for a file picked from GitHub.
    static func canonicalString(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        return canonical(url).absoluteString
    }

    /// Only GitHub's raw file host wants the account token; avatars and everything else are public.
    static func needsToken(_ url: URL) -> Bool {
        url.host == "raw.githubusercontent.com"
    }

    /// The file behind a stored `file://` URL, following it into the current app container when
    /// the stored path belongs to a previous one.
    static func resolve(fileURL: URL) -> URL? {
        if FileManager.default.fileExists(atPath: fileURL.path) { return fileURL }
        let name = fileURL.lastPathComponent
        for directory in [FileManager.SearchPathDirectory.applicationSupportDirectory, .documentDirectory] {
            guard let base = FileManager.default.urls(for: directory, in: .userDomainMask).first else { continue }
            let candidate = base.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    // MARK: Disk cache

    private static var cacheDirectory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let directory = caches.appendingPathComponent("RepoIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func cacheFile(for url: URL) -> URL? {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory?.appendingPathComponent(name)
    }

    private static func diskCached(_ url: URL) -> Data? {
        guard let file = cacheFile(for: url) else { return nil }
        return FileManager.default.contents(atPath: file.path)
    }

    private static func diskStore(_ data: Data, for url: URL) {
        guard let file = cacheFile(for: url) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

// MARK: - View

/// An icon from `RepoIconStore`: the placeholder with a small spinner while loading, the image
/// once it is there, the placeholder alone if it never comes.
struct StoredRepoIcon<Placeholder: View>: View {
    let url: URL
    var tokenKey: String?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
            if isLoading && image == nil {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        // Read the memory cache synchronously so an already-seen icon never flashes a placeholder
        // while `.task` spins up.
        .onAppear { image = image ?? ImageCache.shared.image(for: RepoIconStore.canonical(url)) }
        .task(id: url) {
            if let cached = ImageCache.shared.image(for: RepoIconStore.canonical(url)) {
                image = cached
                return
            }
            image = nil
            isLoading = true
            defer { isLoading = false }
            image = await RepoIconStore.shared.image(for: url, tokenKey: tokenKey)
        }
    }
}
