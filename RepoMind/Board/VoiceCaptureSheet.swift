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

    private var drafts: [CaptureDraft] { viewModel.pendingCapture?.drafts ?? [] }

    /// The binding to one card, found by its id every time it is read, so that removing a card or saving
    /// cannot leave a row reading an index that is gone ("Index out of range").
    private func binding(for id: UUID) -> Binding<CaptureDraft> {
        Binding(
            get: { viewModel.pendingCapture?.drafts.first { $0.id == id } ?? CaptureDraft(title: "") },
            set: { updated in
                guard let index = viewModel.pendingCapture?.drafts.firstIndex(where: { $0.id == id }) else { return }
                viewModel.pendingCapture?.drafts[index] = updated
            })
    }

    private var canSave: Bool {
        drafts.contains { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            // Not while the microphone is open: the words it has not delivered yet would be lost.
            && !viewModel.voiceManager.isRecording
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if capture?.isComposing == true {
                            CaptureComposingRow()
                        } else if let capture, !capture.composedByAI, aiEnabled, !VoiceComposer.isAvailable {
                            CaptureNoteRow(key: "capture_ai_unavailable", symbol: "cpu")
                        } else if capture?.composedByAI == true {
                            CaptureNoteRow(key: "capture_ai_badge", symbol: "sparkles")
                        }
                        ForEach(drafts) { draft in
                            CaptureDraftCard(
                                draft: binding(for: draft.id), repos: nil, columns: columns,
                                defaultColumnTitle: String(localized: "capture_column_current"),
                                canRemove: drafts.count > 1,
                                onRemove: { viewModel.pendingCapture?.drafts.removeAll { $0.id == draft.id } })
                        }
                        if let capture {
                            CaptureTranscriptCard(transcript: capture.transcript)
                        }
                    }
                    .padding(.horizontal, HomeTheme.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 90)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom) { CaptureDictateBar(voiceManager: viewModel.voiceManager) }
            .navigationTitle("capture_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("capture_discard", role: .destructive) { viewModel.discardCapture() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(format: String(localized: "capture_save %lld"), drafts.count)) {
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
}
