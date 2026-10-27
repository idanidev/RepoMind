import Foundation

/// A link the app is willing to open because somebody else said so: an app's statistics endpoint
/// puts one on each report, and a notification carries one in its payload. Anything but a plain
/// https address is dropped, so a hostile or broken backend cannot make a tap launch another app
/// (`tel:`, a custom scheme), show a page without TLS, or carry credentials in the URL.
nonisolated enum SafeLink {
    static func web(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return web(url: url)
    }

    static func web(url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
            url.user == nil, url.password == nil
        else { return nil }
        return url
    }
}
