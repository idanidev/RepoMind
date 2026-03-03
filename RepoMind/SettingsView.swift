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
                        Label("Simular Pro", systemImage: "crown.fill")
                            .foregroundStyle(.purple)
                    }
                    .tint(.purple)

                    if subscription.isMockPro {
                        Text("La app se comporta como usuario Pro.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Solo visible en builds de desarrollo. No tiene efecto en producción.")
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

                    Link("privacy_policy", destination: URL(string: "https://idanidev.github.io/repomind/privacy")!)
                    Link("terms_of_use", destination: URL(string: "https://idanidev.github.io/repomind/terms")!)
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
        struct BTask: Codable {
            let content: String
            let status: String
            let orderIndex: Int
        }
        struct BColumn: Codable {
            let name: String
            let orderIndex: Int
            let colorHex: String
            let tasks: [BTask]
        }
        struct BRepo: Codable {
            let name: String
            let description: String
            let isLocal: Bool
            let logoURL: String?
            let columns: [BColumn]
        }
        struct BRoot: Codable {
            let version: Int
            let exportedAt: String
            let repos: [BRepo]
        }

        let repoBackups = repos.map { repo -> BRepo in
            let cols = (repo.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }
            let colBackups = cols.map { col -> BColumn in
                let tasks = (col.tasks ?? []).sorted { $0.orderIndex < $1.orderIndex }
                let taskBackups = tasks.map { BTask(content: $0.content, status: $0.status, orderIndex: $0.orderIndex) }
                return BColumn(name: col.name, orderIndex: col.orderIndex, colorHex: col.colorHex, tasks: taskBackups)
            }
            return BRepo(name: repo.name, description: repo.repoDescription, isLocal: repo.isLocal, logoURL: repo.logoURL, columns: colBackups)
        }

        let root = BRoot(
            version: 1,
            exportedAt: ISO8601DateFormatter().string(from: .now),
            repos: repoBackups
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(root)
    }

    // MARK: - Import

    private func handleImport(_ result: Result<[URL], Error>) async {
        isImporting = true
        defer { isImporting = false }

        do {
            guard let url = try result.get().first else { return }

            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)

            struct BTask: Codable {
                let content: String
                let status: String
                let orderIndex: Int
            }
            struct BColumn: Codable {
                let name: String
                let orderIndex: Int
                let colorHex: String
                let tasks: [BTask]
            }
            struct BRepo: Codable {
                let name: String
                let description: String
                let isLocal: Bool
                let logoURL: String?
                let columns: [BColumn]
            }
            struct BRoot: Codable {
                let version: Int
                let exportedAt: String
                let repos: [BRepo]
            }

            let backup = try JSONDecoder().decode(BRoot.self, from: data)

            for repoData in backup.repos {
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
