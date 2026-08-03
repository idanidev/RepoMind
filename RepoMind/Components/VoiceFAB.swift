import SwiftUI

struct VoiceFAB: View {
    @Bindable var voiceManager: VoiceManager
    let onComplete: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var pulseScale: CGFloat = 1.0
    @State private var buttonScale: CGFloat = 1.0

    private static let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    private var fabSize: CGFloat {
        #if targetEnvironment(macCatalyst)
            return 48
        #else
            return horizontalSizeClass == .regular ? 64 : 56
        #endif
    }

    private var pulseSize: CGFloat { fabSize + 8 }

    private var fabLabel: some View {
        ZStack {
            if voiceManager.isRecording {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .scaleEffect(pulseScale)
                    .frame(width: pulseSize, height: pulseSize)
            }

            if voiceManager.isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.5), lineWidth: 3)
                    .scaleEffect(1.0 + CGFloat(voiceManager.audioLevel) * 0.4)
                    .frame(width: fabSize, height: fabSize)
            }

            Circle()
                .fill(voiceManager.isRecording ? Color.red : Color.accentColor)
                .frame(width: fabSize, height: fabSize)
                .shadow(
                    color: (voiceManager.isRecording ? Color.red : Color.accentColor)
                        .opacity(0.35), radius: 10, y: 4)

            Image(systemName: voiceManager.isRecording ? "stop.fill" : "mic.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .scaleEffect(buttonScale)
    }

    private func openSettings() {
        // UIApplication.openSettingsURLString works on both iOS and Mac Catalyst
        // (Mac Catalyst runs on UIKit, so #if os(iOS) incorrectly excluded it)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var isAlertPresented: Binding<Bool> {
        Binding(
            get: { voiceManager.errorMessage != nil },
            set: { if !$0 { voiceManager.errorMessage = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            // Transcription preview
            if voiceManager.isRecording && !voiceManager.transcribedText.isEmpty {
                Text(voiceManager.transcribedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: 200)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityLabel("Live transcript: \(voiceManager.transcribedText)")
            }

            // FAB button
            Button {
                // Immediate haptic on press
                Self.impactFeedback.impactOccurred()

                // Immediate scale animation
                withAnimation(.spring(duration: 0.15)) {
                    buttonScale = 0.85
                }
                withAnimation(.spring(duration: 0.2).delay(0.1)) {
                    buttonScale = 1.0
                }

                Task {
                    if voiceManager.isRecording {
                        voiceManager.stopRecording()
                    } else {
                        await voiceManager.toggleRecording()
                    }
                }
            } label: {
                fabLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                voiceManager.isRecording
                    ? "voice_stop_recording"
                    : "voice_start_recording"
            )
            .accessibilityHint(
                voiceManager.isRecording ? "voice_stop_hint" : "voice_start_hint"
            )
            .accessibilityValue(
                voiceManager.isRecording ? "voice_recording_value" : "voice_stopped_value"
            )
            .accessibilityAddTraits(.startsMediaSession)
            // Only show language toggle if Dual Mode is OFF
            .contextMenu {
                if !voiceManager.useDualLanguage {
                    Button {
                        voiceManager.switchLocale()
                    } label: {
                        Label(
                            voiceManager.speechLocale.identifier.starts(with: "es")
                                ? "voice_switch_to_english" : "voice_switch_to_spanish",
                            systemImage: "globe"
                        )
                    }
                }
            }
        }
        .animation(.spring(duration: 0.4), value: voiceManager.isRecording)
        .animation(.spring(duration: 0.3), value: voiceManager.transcribedText)
        .onChange(of: voiceManager.isRecording) { oldValue, recording in
            if recording {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.4
                }
            } else {
                pulseScale = 1.0
                // Call onComplete when recording stops (manual, silence, or smart routing)
                if oldValue && !voiceManager.transcribedText.isEmpty {
                    onComplete()
                }
            }
        }
        .alert(
            "permission_required_title",
            isPresented: isAlertPresented
        ) {
            Button("open_settings_button") {
                openSettings()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text(voiceManager.errorMessage ?? "")
        }
    }
}
