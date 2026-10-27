import SwiftUI

// MARK: - Review sheet

/// What the microphone heard, with its shape, before anything is saved. The title and the
/// details can be edited, the column and the kind picked, more can be dictated, and nothing
/// reaches the board until Save. Several subjects in one dictation arrive as several drafts.
struct VoiceCaptureSheet: View {
    @Bindable var viewModel: KanbanViewModel
    let columns: [String]

    @AppStorage("voiceAIEnabled") private var aiEnabled = true

    private var capture: VoiceCapture? { viewModel.pendingCapture }

    private var drafts: Binding<[CaptureDraft]> {
        Binding(
            get: { viewModel.pendingCapture?.drafts ?? [] },
            set: { viewModel.pendingCapture?.drafts = $0 })
    }

    private var canSave: Bool {
        drafts.wrappedValue.contains { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if capture?.isComposing == true {
                            composing
                        } else if let capture, !capture.composedByAI, aiEnabled, !VoiceComposer.isAvailable {
                            note("capture_ai_unavailable", symbol: "cpu")
                        } else if capture?.composedByAI == true {
                            note("capture_ai_badge", symbol: "sparkles")
                        }
                        ForEach(drafts) { $draft in
                            draftCard($draft)
                        }
                        if let capture {
                            transcriptCard(capture.transcript)
                        }
                    }
                    .padding(.horizontal, HomeTheme.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 90)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom) { dictateBar }
            .navigationTitle("capture_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("capture_discard", role: .destructive) { viewModel.discardCapture() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(format: String(localized: "capture_save %lld"), drafts.wrappedValue.count)) {
                        viewModel.saveCapture()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(HomeTheme.background)
        .interactiveDismissDisabled()
    }

    // MARK: Pieces

    private var composing: some View {
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

    private func note(_ key: LocalizedStringKey, symbol: String) -> some View {
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

    private func draftCard(_ draft: Binding<CaptureDraft>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("capture_title_placeholder", text: draft.title, axis: .vertical)
                .font(.headline)
                .foregroundStyle(HomeTheme.textPrimary)
                .lineLimit(1...4)
            TextField("capture_details_placeholder", text: draft.details, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(HomeTheme.textPrimary)
                .lineLimit(1...8)
            Toggle(isOn: draft.delegate) {
                Label("capture_delegate", systemImage: "cpu")
                    .font(.footnote)
                    .foregroundStyle(HomeTheme.textPrimary)
            }
            .tint(HomeTheme.accent)
            HStack(spacing: 8) {
                kindMenu(draft.kind)
                columnMenu(draft.columnName)
                Spacer()
                if drafts.wrappedValue.count > 1 {
                    Button {
                        drafts.wrappedValue.removeAll { $0.id == draft.wrappedValue.id }
                    } label: {
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
    }

    private func kindMenu(_ kind: Binding<CaptureKind>) -> some View {
        Menu {
            Picker("capture_kind", selection: kind) {
                ForEach(CaptureKind.allCases) { option in
                    Label(labelText(for: option), systemImage: option.symbol).tag(option)
                }
            }
        } label: {
            HomeChip(symbol: kind.wrappedValue.symbol, text: labelText(for: kind.wrappedValue))
        }
    }

    private func columnMenu(_ column: Binding<String?>) -> some View {
        Menu {
            Picker("capture_column", selection: column) {
                Text("capture_column_current").tag(nil as String?)
                ForEach(columns, id: \.self) { name in
                    Text(name).tag(name as String?)
                }
            }
        } label: {
            HomeChip(
                symbol: "rectangle.split.3x1",
                text: column.wrappedValue ?? String(localized: "capture_column_current"),
                tint: HomeTheme.accent)
        }
    }

    private func labelText(for kind: CaptureKind) -> String {
        switch kind {
        case .bug: String(localized: "capture_kind_bug")
        case .feature: String(localized: "capture_kind_feature")
        case .idea: String(localized: "capture_kind_idea")
        case .chore: String(localized: "capture_kind_chore")
        }
    }

    private func transcriptCard(_ transcript: String) -> some View {
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

    /// The same microphone: stopping it appends what it heard to the open capture.
    private var dictateBar: some View {
        let recording = viewModel.voiceManager.isRecording
        return Button {
            Task { await viewModel.voiceManager.toggleRecording() }
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
