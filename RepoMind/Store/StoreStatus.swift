import Foundation

// MARK: - Store status

/// What App Store Connect says about the developer's apps, in the shape of `docs/store-contract.md`.
///
/// RepoMind never talks to Apple: a scheduled workflow in the developer's own repo reads App Store
/// Connect with the API key, and writes this JSON for the app to read, so the key never lives on a
/// phone. This file is the reading side: the model, and the rules that say which version is out,
/// which one is waiting, and whether a build is sitting in TestFlight unsent.
nonisolated struct StoreStatus: Codable, Hashable, Sendable {
    static let supportedSchema = 1

    var schema: Int
    var generatedAt: Date
    var apps: [StoreApp] = []

    nonisolated struct StoreApp: Codable, Hashable, Sendable, Identifiable {
        /// The app's Apple ID.
        var id: String
        var name: String
        var bundleId: String
        /// The GitHub repo this app is built from, when the workflow's map says so.
        var repo: String?
        /// Newest first, every platform.
        var versions: [Version] = []
        /// Newest first.
        var builds: [Build] = []
        /// Absent without a vendor number, or with a key that cannot see sales.
        var sales: Sales?

        init(
            id: String, name: String, bundleId: String, repo: String? = nil, versions: [Version] = [],
            builds: [Build] = [], sales: Sales? = nil
        ) {
            self.id = id
            self.name = name
            self.bundleId = bundleId
            self.repo = repo
            self.versions = versions
            self.builds = builds
            self.sales = sales
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            bundleId = try container.decode(String.self, forKey: .bundleId)
            repo = try container.decodeIfPresent(String.self, forKey: .repo)
            versions = try container.decodeIfPresent([Version].self, forKey: .versions) ?? []
            builds = try container.decodeIfPresent([Build].self, forKey: .builds) ?? []
            sales = try container.decodeIfPresent(Sales.self, forKey: .sales)
        }
    }

    nonisolated struct Version: Codable, Hashable, Sendable, Identifiable {
        /// `IOS`, `MAC_OS`, `TV_OS`, `VISION_OS`.
        var platform: String?
        var version: String
        /// Apple's state, as it came.
        var state: String
        var createdAt: Date?

        var id: String { "\(platform ?? "")-\(version)" }
        var kind: StoreVersionState { StoreVersionState(raw: state) }
    }

    nonisolated struct Build: Codable, Hashable, Sendable, Identifiable {
        /// The marketing version the build belongs to.
        var version: String?
        var build: String
        var uploadedAt: Date?
        var state: String?
        var expired = false

        var id: String { build }
        var isUsable: Bool { !expired && (state == nil || state == "VALID") }
    }

    nonisolated struct Sales: Codable, Hashable, Sendable {
        /// The last closed day, `YYYY-MM-DD`, in Apple's Pacific time.
        var through: String
        /// Oldest first, one entry per day.
        var daily: [Day] = []
    }

    nonisolated struct Day: Codable, Hashable, Sendable, Identifiable {
        var date: String
        var downloads: Int
        var updates: Int
        var purchases: Int

        var id: String { date }
    }

    static func decode(_ data: Data) throws -> StoreStatus {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = RepoStats.date(fromISO8601: text) { return date }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(text)"))
        }
        let status = try decoder.decode(StoreStatus.self, from: data)
        guard status.schema == supportedSchema else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Unsupported store schema \(status.schema)"))
        }
        return status
    }

    /// Numeric, component by component: 1.5.10 is newer than 1.5.9, which a string compare gets wrong.
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }
}

// MARK: - Version state

/// What Apple's `appStoreState` means for the developer, in the handful of cases the app tells apart.
nonisolated enum StoreVersionState: Hashable, Sendable {
    /// `READY_FOR_SALE`: the one users download.
    case live
    case waitingForReview
    case inReview
    /// Approved and waiting for the developer, or for Apple, to release it.
    case approved
    case rejected
    /// Being prepared, or waiting to be submitted.
    case draft
    case processing
    case removed
    case replaced
    case other

    init(raw: String) {
        switch raw {
        case "READY_FOR_SALE": self = .live
        case "WAITING_FOR_REVIEW": self = .waitingForReview
        case "IN_REVIEW": self = .inReview
        case "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "APPROVED": self = .approved
        case "REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY": self = .rejected
        case "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "WAITING_FOR_EXPORT_COMPLIANCE", "ACCEPTED": self = .draft
        case "PROCESSING_FOR_APP_STORE", "PROCESSING_FOR_DISTRIBUTION": self = .processing
        case "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE": self = .removed
        case "REPLACED_WITH_NEW_VERSION": self = .replaced
        default: self = .other
        }
    }

    /// A version on its way to the store, as opposed to one that is out or that nobody will see again.
    var isPending: Bool {
        switch self {
        case .waitingForReview, .inReview, .approved, .rejected, .draft, .processing: true
        case .live, .removed, .replaced, .other: false
        }
    }
}

// MARK: - Per platform

/// One platform of one app: the version users have, and the one on its way, if any.
nonisolated struct StoreRelease: Hashable, Sendable, Identifiable {
    var platform: String
    var live: StoreStatus.Version?
    var pending: StoreStatus.Version?

    var id: String { platform }

    /// "iOS", "macOS", ... for the names Apple writes in capitals.
    var platformName: String {
        switch platform {
        case "IOS": "iOS"
        case "MAC_OS": "macOS"
        case "TV_OS": "tvOS"
        case "VISION_OS": "visionOS"
        default: platform
        }
    }
}

/// Plain values and no models, so it is `nonisolated` like the type it extends: the alert rules and
/// the tests read it from outside the main actor.
nonisolated extension StoreStatus.StoreApp {
    /// A release per platform, in the order the platforms first appear (the newest version's first).
    ///
    /// Live is the newest version Apple says is for sale. Pending is the newest version that is on its
    /// way and was created after it: a draft older than the live version is leftover, not news.
    var releases: [StoreRelease] {
        var order: [String] = []
        for version in versions {
            let platform = version.platform ?? ""
            if !order.contains(platform) { order.append(platform) }
        }
        return order.map { platform in
            let ofPlatform = versions.filter { ($0.platform ?? "") == platform }
            let liveIndex = ofPlatform.firstIndex { $0.kind == .live }
            let pending = ofPlatform.prefix(liveIndex ?? ofPlatform.count).first { $0.kind.isPending }
            return StoreRelease(platform: platform, live: liveIndex.map { ofPlatform[$0] }, pending: pending)
        }
    }

    /// The release a TestFlight build is compared with: iOS when the app has it, else the first.
    var primaryRelease: StoreRelease? {
        releases.first { $0.platform == "IOS" } ?? releases.first
    }

    var latestBuild: StoreStatus.Build? { builds.first { $0.isUsable } }

    /// The newest usable build, when it carries a version newer than the live one and no version of
    /// that number is in review: built, uploaded, and never sent. The thing that sits in TestFlight
    /// for two weeks because nobody pressed the button.
    var unsubmittedBuild: StoreStatus.Build? {
        guard let build = latestBuild, let version = build.version else { return nil }
        let release = primaryRelease
        if let live = release?.live, !StoreStatus.isNewer(version, than: live.version) { return nil }
        if let pending = release?.pending, pending.version == version { return nil }
        return build
    }

    /// Whether the app is the one a repo is built from: the workflow's explicit map first, then the
    /// repo's name inside the app's name or bundle id ("InSync" in "com.idanidev.syncrocalendar" misses,
    /// which is why the map exists).
    func matches(repoName: String) -> Bool {
        let wanted = CaptureRepoResolver.squash(repoName)
        guard wanted.count >= 3 else { return false }
        if let repo { return CaptureRepoResolver.squash(repo) == wanted }
        return [name, bundleId].contains { CaptureRepoResolver.squash($0).contains(wanted) }
    }

    var downloads: StoreDownloads? {
        sales.map { StoreDownloads(sales: $0) }
    }
}

// MARK: - Downloads

/// The sales report as the numbers the card shows. Downloads are first downloads: a redownload by
/// someone who already had the app is not a new user.
nonisolated struct StoreDownloads: Hashable, Sendable {
    /// The last day Apple has closed.
    let through: Date?
    /// Oldest first.
    let days: [StoreStatus.Day]

    init(sales: StoreStatus.Sales) {
        through = RepoStats.day(from: sales.through)
        days = sales.daily.sorted { $0.date < $1.date }
    }

    func downloads(lastDays count: Int) -> Int { days.suffix(count).reduce(0) { $0 + $1.downloads } }
    func updates(lastDays count: Int) -> Int { days.suffix(count).reduce(0) { $0 + $1.updates } }
    func purchases(lastDays count: Int) -> Int { days.suffix(count).reduce(0) { $0 + $1.purchases } }

    var last7: Int { downloads(lastDays: 7) }
    var last30: Int { downloads(lastDays: 30) }
    var sparkline: [Int] { days.map(\.downloads) }
    /// Whether anything at all happened in the window, so a brand-new app is not drawn as a flat line.
    var hasActivity: Bool { days.contains { $0.downloads + $0.updates + $0.purchases > 0 } }
}
