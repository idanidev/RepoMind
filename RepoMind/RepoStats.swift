import Foundation

// MARK: - Repo stats

/// The statistics contract an app serves to RepoMind (`docs/stats-contract.md`, version 1).
///
/// RepoMind collects nothing: each app's own backend aggregates what its admin panel shows and
/// serves it in this shape, and RepoMind draws it the same way for every app. Everything but
/// the header is optional, so an app without subscriptions or crash reports simply says less.
nonisolated struct RepoStats: Codable, Hashable, Sendable {
    static let supportedSchema = 1

    var schema: Int
    var app: String
    var generatedAt: Date
    var periodDays: Int
    var headline: [Headline] = []
    var signals: [Signal] = []
    var features: [Feature] = []
    var series: [Series] = []
    var versions: [Version] = []
    var issues: [Issue] = []

    /// A number for the top of the page, with an optional previous value for the arrow.
    nonisolated struct Headline: Codable, Hashable, Sendable, Identifiable {
        var key: String
        var label: String
        var value: Int?
        var previous: Int?
        var primary: Bool?

        var id: String { key }
    }

    /// One counter, current period against the one before.
    nonisolated struct Signal: Codable, Hashable, Sendable, Identifiable {
        var key: String
        var current: Int
        var previous: Int

        var id: String { key }

        /// The first segment of the key: `pantalla.compra` belongs to `pantalla`.
        var family: String { key.split(separator: ".").first.map(String.init) ?? key }
    }

    /// How many of the population have used a feature, ever and lately.
    nonisolated struct Feature: Codable, Hashable, Sendable, Identifiable {
        var key: String
        var label: String
        var adopters: Int
        var activeAdopters: Int
        var population: Int

        var id: String { key }
    }

    nonisolated struct Series: Codable, Hashable, Sendable, Identifiable {
        var key: String
        var label: String
        var points: [Point] = []

        var id: String { key }
    }

    /// `date` is a calendar day as `YYYY-MM-DD`, with no time or zone.
    nonisolated struct Point: Codable, Hashable, Sendable {
        var date: String
        var value: Int
    }

    nonisolated struct Version: Codable, Hashable, Sendable, Identifiable {
        var version: String?
        var current: Int

        var id: String { version ?? "" }
    }

    nonisolated struct Issue: Codable, Hashable, Sendable, Identifiable {
        var kind: String
        var title: String
        var at: Date
        var count: Int
        var version: String?
        var url: String?
        var status: String?

        var id: String { "\(kind)-\(at.timeIntervalSince1970)-\(title)" }
        var isCrash: Bool { kind == "crash" }
    }

    /// The signals of one family, `pantalla.*`, most used first.
    nonisolated struct SignalFamily: Hashable, Sendable, Identifiable {
        var family: String
        var signals: [Signal]

        var id: String { family }
    }

    // MARK: Derived

    /// The headline marked `primary`, or the first one, for the repo card.
    var primaryHeadline: Headline? {
        headline.first { $0.primary == true } ?? headline.first
    }

    /// Signals grouped by family, families and signals both ordered by current use.
    var signalFamilies: [SignalFamily] {
        let grouped = Dictionary(grouping: signals, by: \.family)
        return grouped
            .map { SignalFamily(family: $0.key, signals: $0.value.sorted { $0.current > $1.current }) }
            .sorted { lhs, rhs in
                let left = lhs.signals.reduce(0) { $0 + $1.current }
                let right = rhs.signals.reduce(0) { $0 + $1.current }
                return left != right ? left > right : lhs.family < rhs.family
            }
    }

    /// Change from the previous period, in parts per one. `nil` when there was nothing
    /// before: going from zero to ten is not "a thousand percent", it is a start.
    static func change(current: Int, previous: Int?) -> Double? {
        guard let previous, previous > 0 else { return nil }
        return (Double(current) - Double(previous)) / Double(previous)
    }

    // MARK: Decoding

    /// Dates arrive as ISO 8601 with a zone and, from Postgres, six fractional digits, which
    /// `ISO8601DateFormatter` does not take: the fraction is trimmed before parsing.
    static func decode(_ data: Data) throws -> RepoStats {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = date(fromISO8601: text) {
                return date
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(text)"))
        }
        let stats = try decoder.decode(RepoStats.self, from: data)
        guard stats.schema == supportedSchema else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Unsupported stats schema \(stats.schema)"))
        }
        return stats
    }

    static func date(fromISO8601 text: String) -> Date? {
        if let date = iso.date(from: text) { return date }
        guard let dot = text.firstIndex(of: ".") else { return nil }
        var end = text.index(after: dot)
        while end < text.endIndex, text[end].isNumber { end = text.index(after: end) }
        let digits = String(text[text.index(after: dot)..<end].prefix(3))
        let fraction = digits.padding(toLength: 3, withPad: "0", startingAt: 0)
        return isoWithFractions.date(from: String(text[..<dot]) + "." + fraction + String(text[end...]))
    }

    private static let isoWithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// `YYYY-MM-DD` to a date at local midnight, for the charts.
    static func day(from text: String) -> Date? {
        dayFormatter.date(from: text)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
