import StoreKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Backup Document

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Backup DTOs (shared between export and import)

private enum BackupDTO {
    struct Task: Codable {
        let content: String
        let status: String
        let orderIndex: Int
    }
    struct Column: Codable {
        let name: String
        let orderIndex: Int
        let colorHex: String
        let tasks: [Task]
    }
    struct Repo: Codable {
        let name: String
        let description: String
        let isLocal: Bool
        let logoURL: String?
        let columns: [Column]
    }
    struct Root: Codable {
        let version: Int
        let exportedAt: String
        let repos: [Repo]
    }
}

// MARK: - Settings View

struct SettingsView: View {
    /// `true` when shown as a tab of the redesigned home rather than as a sheet: no
    /// navigation stack of its own, and no Done button to dismiss.
    var embedded = false
    /// Set by the home, which keeps Profile behind Settings: a row at the top opens it.
    var onOpenProfile: (() -> Void)?

    @AppStorage("voiceAIEnabled") private var voiceAIEnabled = true
    @AppStorage("voiceSilenceSeconds") private var voiceSilenceSeconds = 3.0
    @AppStorage("voiceCustomVocabulary") private var voiceCustomVocabulary = ""
    @AppStorage("alerts_ci") private var alertsCI = true
    @AppStorage("alerts_releases") private var alertsReleases = true
    @AppStorage("alerts_security") private var alertsSecurity = true
    @AppStorage("alerts_crashes") private var alertsCrashes = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query private var repos: [ProjectRepo]

    @State private var showPaywall = false
    @State private var showManageSubscription = false
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var backupDocument: BackupDocument?
    @State private var isImporting = false
    @State private var showOnboardingPreview = false

    private let subscription = SubscriptionManager.shared
    private let syncMonitor = CloudKitSyncMonitor.shared

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        Group {
            if embedded {
                settingsList
            } else {
                NavigationStack { settingsList }
            }
        }
        .presentationDetents([.large])
        .frame(idealWidth: 500)
    }

    /// The list itself, without the stack: the home's Settings tab embeds it under its own
    /// header, inside the home's navigation stack.
    private var settingsList: some View {
        List {
            if let onOpenProfile {
                Section {
                    Button(action: onOpenProfile) {
                        HStack {
                            Label("home_tab_profile", systemImage: "person.crop.circle")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }

            // MARK: - Subscription

            Section("subscription_header") {
                HStack {
                    Label(
                        "current_plan_label",
                        systemImage: subscription.isPro ? "crown.fill" : "person.fill"
                    )
                    Spacer()
                    Text(subscription.currentPlanName)
                        .foregroundStyle(subscription.isPro ? .purple : .secondary)
                        .font(.subheadline.weight(.semibold))
                }

                if subscription.isPro && !subscription.isMockPro {
                    Button("manage_subscription_button") {
                        showManageSubscription = true
                    }
                } else if !subscription.isPro {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("upgrade_to_pro_button", systemImage: "crown")
                            .foregroundStyle(.purple)
                    }
                }

                Button {
                    Task {
                        do {
                            let restored = try await subscription.restorePurchases()
                            if restored {
                                ToastManager.shared.show(
                                    String(localized: "restore_success_toast"),
                                    style: .success
                                )
                            } else {
                                ToastManager.shared.show(
                                    String(localized: "restore_no_purchases_toast"),
                                    style: .info
                                )
                            }
                        } catch {
                            ToastManager.shared.show(error.localizedDescription, style: .error)
                        }
                    }
                } label: {
                    if subscription.isRestoring {
                        HStack {
                            Text("restore_purchases_button")
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    } else {
                        Text("restore_purchases_button")
                    }
                }
                .disabled(subscription.isRestoring)
            }

            // MARK: - iCloud sync health

            // Only rendered when something is actually wrong. A silent sync failure used to be
            // completely invisible, which is how one went unnoticed for months.
            if syncMonitor.hasSyncProblem {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.icloud")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("icloud_sync_problem_title")
                                .font(.subheadline.weight(.semibold))
                            if let detail = syncMonitor.lastErrorDetail {
                                Text(detail).font(.caption)
                            }
                            if let message = syncMonitor.lastErrorMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("icloud_sync_section")
                } footer: {
                    Text("icloud_sync_problem_footer")
                }
            }

            // MARK: - Task sync

            Section {
                NavigationLink {
                    IssueSyncSettingsView()
                } label: {
                    HStack {
                        Label(
                            "issue_sync_settings_title",
                            systemImage: "arrow.trianglehead.2.clockwise")
                        Spacer()
                        Text("\(repos.filter(\.syncTasksToGitHub).count)/\(repos.filter { !$0.isLocal }.count)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("issue_sync_section_header")
            }

            // MARK: - Backup

            Section {
                Button {
                    exportBackup()
                } label: {
                    Label("export_backup_button", systemImage: "square.and.arrow.up")
                }
                .disabled(repos.isEmpty)

                Button {
                    showImporter = true
                } label: {
                    if isImporting {
                        HStack {
                            Text("import_backup_button")
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    } else {
                        Label("import_backup_button", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isImporting)
            } header: {
                Text("backup_section_header")
            } footer: {
                Text("backup_footer")
            }

            // MARK: - Debug (solo en desarrollo)

            #if DEBUG
            Section {
                Toggle(isOn: Binding(
                    get: { subscription.isMockPro },
                    set: { subscription.isMockPro = $0 }
                )) {
                    Label("debug_simulate_pro_label", systemImage: "crown.fill")
                        .foregroundStyle(.purple)
                }
                .tint(.purple)

                if subscription.isMockPro {
                    Text("debug_simulate_pro_hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Otherwise the only way to see the onboarding again is deleting the app,
                // which also throws away the local data you were testing with.
                Button {
                    showOnboardingPreview = true
                } label: {
                    Label("debug_replay_onboarding", systemImage: "sparkles.rectangle.stack")
                }
            } header: {
                Text("Debug")
            } footer: {
                Text("debug_only_visible_hint")
            }
            #endif

            // MARK: - About

            // MARK: - Voice

            Section {
                Toggle("voice_ai_toggle", isOn: $voiceAIEnabled)
                Picker("voice_silence_picker", selection: $voiceSilenceSeconds) {
                    Text("voice_silence_2").tag(2.0)
                    Text("voice_silence_3").tag(3.0)
                    Text("voice_silence_5").tag(5.0)
                    Text("voice_silence_never").tag(0.0)
                }
                TextField("voice_vocabulary_placeholder", text: $voiceCustomVocabulary, axis: .vertical)
                    .lineLimit(1...4)
                    .autocorrectionDisabled()
            } header: {
                Text("voice_section_header")
            } footer: {
                Text("voice_ai_footer")
            }

            // MARK: - Alerts (Pro)

            Section {
                Group {
                    Toggle("alerts_ci_toggle", isOn: $alertsCI)
                    Toggle("alerts_releases_toggle", isOn: $alertsReleases)
                    Toggle("alerts_security_toggle", isOn: $alertsSecurity)
                    Toggle("alerts_crashes_toggle", isOn: $alertsCrashes)
                }
                .disabled(!subscription.isPro)
                if !subscription.isPro {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("alerts_pro_button", systemImage: "crown")
                            .foregroundStyle(.purple)
                    }
                }
            } header: {
                Text("alerts_section_header")
            } footer: {
                Text("alerts_footer")
            }
            .onChange(of: [alertsCI, alertsReleases, alertsSecurity, alertsCrashes]) { _, now in
                if now.contains(true) {
                    Task { _ = await FeedbackNotificationManager.shared.requestAuthorizationIfNeeded() }
                }
            }

            Section("about_header") {
                HStack {
                    Text("version_label")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }

                Link("privacy_policy", destination: URL(string: "https://idanidev.github.io/RepoMind/privacy")!)
                Link("terms_of_use", destination: URL(string: "https://idanidev.github.io/RepoMind/terms")!)
            }
        }
        .navigationTitle("settings_title")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("done_button") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        #if DEBUG
            .fullScreenCover(isPresented: $showOnboardingPreview) {
                // Passing onFinish keeps `hasSeenOnboarding` untouched: this is a preview,
                // not a first run.
                OnboardingView { showOnboardingPreview = false }
            }
        #endif
        .manageSubscriptionsSheet(isPresented: $showManageSubscription)
        .fileExporter(
            isPresented: $showExporter,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "repomind-backup"
        ) { result in
            if case .failure(let error) = result {
                ToastManager.shared.show(error.localizedDescription, style: .error)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImport(result) }
        }
    }

    // MARK: - Export

    private func exportBackup() {
        do {
            backupDocument = BackupDocument(data: try buildBackupJSON())
            showExporter = true
        } catch {
            ToastManager.shared.show(error.localizedDescription, style: .error)
        }
    }

    private func buildBackupJSON() throws -> Data {
        let repoBackups = repos.map { repo -> BackupDTO.Repo in
            let cols = (repo.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }
            let colBackups = cols.map { col -> BackupDTO.Column in
                let tasks = (col.tasks ?? []).sorted { $0.orderIndex < $1.orderIndex }
                let taskBackups = tasks.map { BackupDTO.Task(content: $0.content, status: $0.status, orderIndex: $0.orderIndex) }
                return BackupDTO.Column(name: col.name, orderIndex: col.orderIndex, colorHex: col.colorHex, tasks: taskBackups)
            }
            return BackupDTO.Repo(name: repo.name, description: repo.repoDescription, isLocal: repo.isLocal, logoURL: repo.logoURL, columns: colBackups)
        }

        let root = BackupDTO.Root(
            version: 1,
            exportedAt: ISO8601DateFormatter().string(from: .now),
            repos: repoBackups
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(root)
    }

    // MARK: - Import

    @MainActor
    private func handleImport(_ result: Result<[URL], Error>) async {
        isImporting = true
        defer { isImporting = false }

        do {
            guard let url = try result.get().first else { return }

            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)

            let backup = try JSONDecoder().decode(BackupDTO.Root.self, from: data)

            let currentRepoCount = repos.count
            for (index, repoData) in backup.repos.enumerated() {
                guard subscription.canAddRepo(currentCount: currentRepoCount + index) else {
                    ToastManager.shared.show(
                        String(localized: "repo_limit_upgrade"),
                        style: .info
                    )
                    break
                }
                let repo = ProjectRepo(
                    repoID: 0,
                    name: repoData.name,
                    repoDescription: repoData.description,
                    isLocal: repoData.isLocal,
                    logoURL: repoData.logoURL
                )
                context.insert(repo)

                for colData in repoData.columns {
                    let col = KanbanColumn(
                        name: colData.name,
                        orderIndex: colData.orderIndex,
                        colorHex: colData.colorHex,
                        project: repo
                    )
                    context.insert(col)

                    for taskData in colData.tasks {
                        let task = TaskItem(
                            content: taskData.content,
                            status: taskData.status,
                            column: col,
                            project: repo,
                            orderIndex: taskData.orderIndex
                        )
                        context.insert(task)
                    }
                }
            }

            try context.save()

            ToastManager.shared.show(
                String(format: String(localized: "import_success_toast"), backup.repos.count),
                style: .success
            )
        } catch {
            ToastManager.shared.show(error.localizedDescription, style: .error)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [ProjectRepo.self, KanbanColumn.self, TaskItem.self], inMemory: true)
}
