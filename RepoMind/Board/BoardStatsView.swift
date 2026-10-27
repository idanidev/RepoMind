import Foundation
import SwiftUI

// MARK: - Stats page

/// The statistics of one app, as its backend serves them in the RepoMind contract: the
/// headline numbers, a daily chart, what gets used from most to least, adoption by feature, the
/// versions in use and the latest crashes and reports. Pull to refresh; the menu reconnects.
struct BoardStatsView: View {
    let project: ProjectRepo

    @Environment(\.dismiss) private var dismiss
    @State private var store = RepoStatsStore.shared
    @State private var showSetup = false

    private var repoID: Int { project.repoID }
    private var stats: RepoStats? { store.stats(for: repoID) }

    var body: some View {
        ZStack {
            HomeTheme.background
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if let stats {
                        content(stats)
                    } else if store.isConfigured(repoID) {
                        pending
                    } else {
                        notConfigured
                    }
                }
                .padding(.horizontal, HomeTheme.gutter)
                .padding(.bottom, 24)
            }
            .refreshable { await store.refresh(repoID: repoID, force: true) }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: repoID) { await store.refresh(repoID: repoID) }
        .sheet(isPresented: $showSetup) {
            BoardStatsSetupSheet(repoID: repoID, repoName: project.name)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                BoardCircleButton(symbol: "chevron.left", label: "back_button") { dismiss() }
                Spacer()
                if store.loading.contains(repoID) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(HomeTheme.textSecondary)
                }
                Menu {
                    Button {
                        Task { await store.refresh(repoID: repoID, force: true) }
                    } label: {
                        Label("stats_refresh", systemImage: "arrow.clockwise")
                    }
                    Button {
                        showSetup = true
                    } label: {
                        Label("stats_configure", systemImage: "gearshape")
                    }
                } label: {
                    BoardCircleButton.face(symbol: "ellipsis")
                }
                .accessibilityLabel("more_options")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("stats_title")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(HomeTheme.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(HomeTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 6)
    }

    private var subtitle: String {
        guard let stats, let date = store.fetchedAt[repoID] else { return project.name }
        let relative = date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return stats.app + " · " + String(format: String(localized: "stats_updated %@"), relative)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ stats: RepoStats) -> some View {
        if let failure = store.failures[repoID] {
            failureBanner(failure)
        }
        BoardStatsHeadlineGrid(items: stats.headline)
        ForEach(stats.series) { series in
            BoardStatsSeriesCard(series: series, periodDays: stats.periodDays)
        }
        if !stats.signals.isEmpty {
            BoardStatsSignalsCard(stats: stats)
        }
        if !stats.features.isEmpty {
            BoardStatsFeaturesCard(features: stats.features)
        }
        if !stats.versions.isEmpty {
            BoardStatsVersionsCard(versions: stats.versions)
        }
        if !stats.issues.isEmpty {
            BoardStatsIssuesCard(issues: stats.issues)
        }
    }

    // MARK: States

    private var notConfigured: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(HomeTheme.textSecondary)
            Text("stats_not_configured_title")
                .font(.headline)
                .foregroundStyle(HomeTheme.textPrimary)
            Text("stats_not_configured_message")
                .font(.footnote)
                .foregroundStyle(HomeTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                showSetup = true
            } label: {
                Text("stats_configure")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(HomeTheme.accent))
            }
            .buttonStyle(HomeCardButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(BoardStatsCard())
    }

    @ViewBuilder
    private var pending: some View {
        if let failure = store.failures[repoID] {
            failureBanner(failure)
        } else {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(HomeTheme.textSecondary)
                Text("stats_loading")
                    .font(.footnote)
                    .foregroundStyle(HomeTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(BoardStatsCard())
        }
    }

    private func failureBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(HomeTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("stats_error")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeTheme.textPrimary)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(HomeTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
                .fill(HomeTheme.warning.opacity(0.12))
        )
    }
}

// MARK: - Setup sheet

/// The endpoint and the token for one repo. The token never shows again once saved.
struct BoardStatsSetupSheet: View {
    let repoID: Int
    let repoName: String

    @Environment(\.dismiss) private var dismiss
    @State private var store = RepoStatsStore.shared
    @State private var endpoint = ""
    @State private var token = ""
    @State private var isSaving = false
    @State private var errorText: String?

    private var canSave: Bool {
        !isSaving
            && !token.trimmingCharacters(in: .whitespaces).isEmpty
            && URL(string: endpoint.trimmingCharacters(in: .whitespaces)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("stats_endpoint_placeholder", text: $endpoint)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("stats_token_placeholder", text: $token)
                } header: {
                    Text(repoName)
                } footer: {
                    Text("stats_setup_footer")
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                    }
                }
                if store.isConfigured(repoID) {
                    Section {
                        Button(role: .destructive) {
                            Task {
                                await store.disconnect(repoID: repoID)
                                dismiss()
                            }
                        } label: {
                            Text("stats_remove")
                        }
                    }
                }
            }
            .navigationTitle("stats_setup_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_button") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_button") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                endpoint = store.endpoint(for: repoID)?.absoluteString ?? ""
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        let trimmed = endpoint.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme == "https" else {
            errorText = String(localized: "stats_invalid_url")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.configure(repoID: repoID, endpoint: url, token: token.trimmingCharacters(in: .whitespaces))
            await store.refresh(repoID: repoID, force: true)
            if let failure = store.failures[repoID] {
                errorText = failure
                return
            }
            ToastManager.shared.show(String(localized: "stats_saved_toast"), style: .success)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
