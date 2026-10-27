import SwiftData
import SwiftUI

/// Dictate a task from anywhere: the widget, the shortcut, Siri, the Action Button or the
/// `repomind://capture` link open this and the microphone is already on. Say which app and what
/// ("en InSync, arreglar el login"), stop talking, check the card, save.
struct GlobalCaptureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \ProjectRepo.updatedAt, order: .reverse) private var allRepos: [ProjectRepo]

    @State private var model = GlobalCaptureModel()
    @AppStorage("voiceAIEnabled") private var aiEnabled = true

    private var options: [CaptureRepoOption] {
        GlobalCaptureModel.options(from: allRepos, limit: SubscriptionManager.shared.repoLimit)
    }
    private var voice: VoiceManager { model.voiceManager }

    /// The binding to one card, found by its id every time it is read. A binding made from the array
    /// and an index (`ForEach($drafts)`) reads `drafts[index]` after the card has been removed, or after
    /// Save emptied the capture, and traps with "Index out of range"; this one falls back to an empty draft.
    private func binding(for id: UUID) -> Binding<CaptureDraft> {
        Binding(
            get: { model.capture?.drafts.first { $0.id == id } ?? CaptureDraft(title: "") },
            set: { updated in
                guard let index = model.capture?.drafts.firstIndex(where: { $0.id == id }) else { return }
                model.capture?.drafts[index] = updated
            })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeTheme.background.ignoresSafeArea()
                if options.isEmpty {
                    ContentUnavailableView(
                        "quick_add_no_repos_title",
                        systemImage: "tray",
                        description: Text("quick_add_no_repos_subtitle"))
                } else if model.capture != nil {
                    review
                } else if voice.isRecording {
                    listening
                } else {
                    idle
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.capture != nil {
                    CaptureDictateBar(voiceManager: voice)
                }
            }
            .navigationTitle("global_capture_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        model.discard()
                        dismiss()
                    }
                }
                if let capture = model.capture {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(format: String(localized: "capture_save %lld"), capture.drafts.count)) {
                            if model.save(repos: allRepos, context: context) { dismiss() }
                        }
                        .fontWeight(.semibold)
                        // Not while the microphone is open: the words it has not delivered yet would be lost.
                        .disabled(!model.canSave || voice.isRecording)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(HomeTheme.background)
        .interactiveDismissDisabled(model.capture != nil)
        // Again when the first repos arrive: on a cold start from Siri they can come after the sheet, and
        // the microphone never started, with a spinner for ever.
        .task(id: options.isEmpty) {
            guard !options.isEmpty, !model.hasListened else { return }
            await model.start(options: options)
        }
        .onChange(of: options) { _, new in model.refreshOptions(new) }
        .onChange(of: voice.isRecording) { old, recording in
            // Stopped by hand, by silence or by "añadir a …": what was heard becomes the card.
            if old, !recording { model.prepare() }
        }
        .onDisappear { model.discard() }
        .alert(
            voice.permissionGranted ? "voice_error_title" : "permission_required_title",
            isPresented: permissionAlert
        ) {
            // Settings only helps when it is a permission that is missing; the other errors (a call
            // took the microphone, the recognizer is unavailable) were all offering it.
            if !voice.permissionGranted {
                Button("open_settings_button") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button(voice.permissionGranted ? "ok" : "cancel", role: .cancel) {}
        } message: {
            Text(voice.errorMessage ?? "")
        }
    }

    private var permissionAlert: Binding<Bool> {
        Binding(
            get: { voice.errorMessage != nil },
            set: { if !$0 { voice.errorMessage = nil } })
    }

    // MARK: Listening

    /// The microphone is on and nothing has been shaped yet: a big target, the live text, and a
    /// hint of what to say, since "which app" is the part people forget.
    private var listening: some View {
        VStack(spacing: 22) {
            Spacer()
            orb
            Text("global_capture_listening")
                .font(.title3.weight(.semibold))
                .foregroundStyle(HomeTheme.textPrimary)
            Group {
                if voice.transcribedText.isEmpty {
                    Text("global_capture_hint")
                } else {
                    Text(verbatim: voice.transcribedText)
                }
            }
            .font(.callout)
            .foregroundStyle(HomeTheme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            // The words change several times a second; VoiceOver should not read each one out.
            .accessibilityAddTraits(.updatesFrequently)
            Spacer()
            Button {
                voice.stopRecording()
            } label: {
                Label("capture_stop_dictating", systemImage: "stop.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(HomeTheme.danger))
            }
            .buttonStyle(HomeCardButtonStyle())
            .padding(.horizontal, HomeTheme.gutter)
            .padding(.bottom, 12)
        }
    }

    /// Breathes with the voice.
    private var orb: some View {
        ZStack {
            Circle()
                .fill(HomeTheme.accent.opacity(0.18))
                .frame(width: 150, height: 150)
                .scaleEffect(1 + CGFloat(voice.audioLevel) * 0.6)
            Circle()
                .fill(HomeTheme.accent)
                .frame(width: 92, height: 92)
            Image(systemName: "mic.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(HomeTheme.onAccent)
        }
        .animation(.easeOut(duration: 0.12), value: voice.audioLevel)
        .accessibilityHidden(true)
    }

    /// Before the microphone started, or after it stopped having heard nothing.
    private var idle: some View {
        VStack(spacing: 14) {
            if model.hasListened {
                Image(systemName: "mic.slash")
                    .font(.system(size: 34))
                    .foregroundStyle(HomeTheme.textSecondary)
                Text("global_capture_nothing_heard")
                    .font(.callout)
                    .foregroundStyle(HomeTheme.textSecondary)
                Button {
                    Task { await model.startListening() }
                } label: {
                    Label("global_capture_try_again", systemImage: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(HomeTheme.accent))
                        .foregroundStyle(HomeTheme.onAccent)
                }
                .buttonStyle(HomeCardButtonStyle())
            } else {
                ProgressView()
                    .tint(HomeTheme.textSecondary)
            }
        }
    }

    // MARK: Review

    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if voice.isRecording {
                    listeningStrip
                }
                notes
                ForEach(model.capture?.drafts ?? []) { draft in
                    CaptureDraftCard(
                        draft: binding(for: draft.id), repos: options, columns: model.columns(for: draft),
                        defaultColumnTitle: String(localized: "global_capture_column_first"),
                        canRemove: (model.capture?.drafts.count ?? 0) > 1,
                        onRemove: { model.capture?.drafts.removeAll { $0.id == draft.id } })
                }
                if !model.canSave, model.capture?.isComposing != true {
                    CaptureNoteRow(key: "global_capture_needs_app", symbol: "exclamationmark.circle")
                }
                if let capture = model.capture {
                    CaptureTranscriptCard(transcript: capture.transcript)
                }
            }
            .padding(.horizontal, HomeTheme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 90)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// More is being dictated onto the open card: what is heard so far, until the microphone stops.
    private var listeningStrip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform")
                .font(.footnote)
                .foregroundStyle(HomeTheme.accent)
                .symbolEffect(.variableColor.iterative, isActive: true)
            Group {
                if voice.transcribedText.isEmpty {
                    Text("global_capture_listening")
                } else {
                    Text(verbatim: voice.transcribedText)
                }
            }
            .font(.footnote)
            .foregroundStyle(HomeTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(HomeDashboardCardBackground())
    }

    @ViewBuilder
    private var notes: some View {
        if model.capture?.isComposing == true {
            CaptureComposingRow()
        } else if let capture = model.capture, !capture.composedByAI, aiEnabled, !VoiceComposer.isAvailable {
            CaptureNoteRow(key: "capture_ai_unavailable", symbol: "cpu")
        } else if model.capture?.composedByAI == true {
            CaptureNoteRow(key: "capture_ai_badge", symbol: "sparkles")
        }
    }
}
