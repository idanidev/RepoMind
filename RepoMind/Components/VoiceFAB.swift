import SwiftData
import SwiftUI

struct VoiceFAB: View {
    @Bindable var voiceManager: VoiceManager
    let onComplete: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var buttonScale: CGFloat = 1.0

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
                    .frame(maxWidth: 200)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityLabel("Transcripción en vivo: \(voiceManager.transcribedText)")
            }

            // FAB button
            Button {
                // Immediate haptic on press
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()

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
                        onComplete()
                    } else {
                        await voiceManager.toggleRecording()
                    }
                }
            } label: {
                ZStack {
                    // Pulse ring
                    if voiceManager.isRecording {
                        Circle()
                            .fill(Color.red.opacity(0.2))
                            .scaleEffect(pulseScale)
                            .frame(width: 64, height: 64)
                    }

                    // Audio level ring
                    if voiceManager.isRecording {
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 3)
                            .scaleEffect(1.0 + CGFloat(voiceManager.audioLevel) * 0.4)
                            .frame(width: 56, height: 56)
                    }

                    // Main button
                    Circle()
                        .fill(voiceManager.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 56, height: 56)
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
            .buttonStyle(.plain)
            .accessibilityLabel(
                voiceManager.isRecording
                    ? "Detener grabación"
                    : "Iniciar grabación de voz"
            )
            .accessibilityHint(
                "Doble toque para \(voiceManager.isRecording ? "detener" : "iniciar") la grabación"
            )
            .accessibilityValue(voiceManager.isRecording ? "Grabando" : "Detenido")
            .accessibilityAddTraits(.startsMediaSession)
        }
        .animation(.spring(duration: 0.4), value: voiceManager.isRecording)
        .animation(.spring(duration: 0.3), value: voiceManager.transcribedText)
        .onChange(of: voiceManager.isRecording) { _, recording in
            if recording {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.4
                }
            } else {
                pulseScale = 1.0
            }
        }
        .alert(
            "Permiso Requerido",
            isPresented: .init(
                get: { voiceManager.errorMessage != nil },
                set: { if !$0 { voiceManager.errorMessage = nil } }
            )
        ) {
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(voiceManager.errorMessage ?? "")
        }
    }
}
