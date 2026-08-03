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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query private var repos: [ProjectRepo]

    @State private var showPaywall = false
    @State private var showManageSubscription = false
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var backupDocument: BackupDocument?
    @State private var isImporting = false

    private let subscription = SubscriptionManager.shared
    private let syncMonitor = CloudKitSyncMonitor.shared

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
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
                } header: {
                    Text("Debug")
                } footer: {
                    Text("debug_only_visible_hint")
                }
                #endif

                // MARK: - About

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
        .presentationDetents([.large])
        .frame(idealWidth: 500)
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
