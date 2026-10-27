import SwiftUI

// MARK: - Draft card

/// One task as the review sheets show it: title and details to edit, the agent switch, the kind
/// and the column, and, when the capture started outside a board, the app it goes to. Shared by
/// the board's sheet and the global one so the two cannot drift apart.
struct CaptureDraftCard: View {
    @Binding var draft: CaptureDraft
    /// The apps it can go to; nil on a board, where the app is the board's own.
    var repos: [CaptureRepoOption]?
    /// The column names of the app the draft is going to.
    var columns: [String]
    /// What a draft with no column named reads as in the column menu.
    var defaultColumnTitle: String
    var canRemove: Bool
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let repos {
                repoMenu(repos)
            }
            TextField("capture_title_placeholder", text: $draft.title, axis: .vertical)
                .font(.headline)
                .foregroundStyle(HomeTheme.textPrimary)
                .lineLimit(1...4)
            TextField("capture_details_placeholder", text: $draft.details, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(HomeTheme.textPrimary)
                .lineLimit(1...8)
            Toggle(isOn: $draft.delegate) {
                Label("capture_delegate", systemImage: "cpu")
                    .font(.footnote)
                    .foregroundStyle(HomeTheme.textPrimary)
            }
            .tint(HomeTheme.accent)
            HStack(spacing: 8) {
                kindMenu
                columnMenu
                Spacer()
                if canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(HomeTheme.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("capture_remove_draft")
                }
            }
        }
        .padding(HomeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeDashboardCardBackground())
        // The column belongs to the app: another app has other columns.
        .onChange(of: draft.repoID) { _, _ in draft.columnName = nil }
    }

    private func repoMenu(_ repos: [CaptureRepoOption]) -> some View {
        let current = repos.first { $0.id == draft.repoID }
        return Menu {
            Picker("global_capture_app", selection: $draft.repoID) {
                if current == nil {
                    Text("global_capture_pick_app").tag(nil as Int?)
                }
                ForEach(repos) { repo in
                    Text(repo.name).tag(repo.id as Int?)
                }
            }
        } label: {
            HomeChip(
                symbol: "folder.fill",
                text: current?.name ?? String(localized: "global_capture_pick_app"),
                tint: current == nil ? HomeTheme.warning : HomeTheme.accent)
        }
    }

    private var kindMenu: some View {
        Menu {
            Picker("capture_kind", selection: $draft.kind) {
                ForEach(CaptureKind.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
        } label: {
            HomeChip(symbol: draft.kind.symbol, text: draft.kind.title)
        }
    }

    private var columnMenu: some View {
        Menu {
            Picker("capture_column", selection: $draft.columnName) {
                Text(defaultColumnTitle).tag(nil as String?)
                ForEach(columns, id: \.self) { name in
                    Text(name).tag(name as String?)
                }
            }
        } label: {
            HomeChip(
                symbol: "rectangle.split.3x1",
                text: draft.columnName ?? defaultColumnTitle,
                tint: HomeTheme.accent)
        }
    }
}

// MARK: - Pieces around the cards

/// The on-device model is still shaping the dictation.
struct CaptureComposingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(HomeTheme.textSecondary)
            Text("capture_composing")
                .font(.footnote)
                .foregroundStyle(HomeTheme.textSecondary)
            Spacer()
        }
        .padding(12)
        .background(HomeDashboardCardBackground())
    }
}

/// A one-line remark above the cards: shaped by the model, or why it was not.
struct CaptureNoteRow: View {
    let key: LocalizedStringKey
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(HomeTheme.info)
            Text(key)
                .font(.caption)
                .foregroundStyle(HomeTheme.textSecondary)
            Spacer(minLength: 0)
        }
    }
}

/// What was actually heard, folded away: the cards are an interpretation of it.
struct CaptureTranscriptCard: View {
    let transcript: String

    var body: some View {
        DisclosureGroup {
            Text(transcript)
                .font(.footnote)
                .foregroundStyle(HomeTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            Text("capture_transcript")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeTheme.textSecondary)
        }
        .tint(HomeTheme.textSecondary)
        .padding(12)
        .background(HomeDashboardCardBackground())
    }
}

/// The same microphone as the board's button: stopping it appends what it heard to the capture.
struct CaptureDictateBar: View {
    let voiceManager: VoiceManager

    var body: some View {
        let recording = voiceManager.isRecording
        return Button {
            Task { await voiceManager.toggleRecording() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: recording ? "stop.fill" : "mic.fill")
                Text(recording ? "capture_stop_dictating" : "capture_keep_dictating")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(recording ? HomeTheme.danger : HomeTheme.accent))
        }
        .buttonStyle(HomeCardButtonStyle())
        .padding(.horizontal, HomeTheme.gutter)
        .padding(.vertical, 8)
        .background(HomeTheme.background)
    }
}
