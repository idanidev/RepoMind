import AVFoundation
import Speech
import SwiftUI

// MARK: - Voice Manager

@MainActor
@Observable
final class VoiceManager {
    // State
    var isRecording = false
    var transcribedText = ""
    var audioLevel: Float = 0
    var errorMessage: String?
    var permissionGranted = false

    // Configurable locale (default: Spanish)
    var speechLocale: Locale = Locale(identifier: "es-ES")

    // Private
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var isAudioSessionWarmed = false

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    }

    // MARK: - Permissions

    func requestPermissions() async {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            errorMessage = "Permiso de reconocimiento de voz denegado. Activa el permiso en Ajustes."
            permissionGranted = false
            return
        }

        let audioGranted: Bool
        if #available(iOS 17, *) {
            audioGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            audioGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard audioGranted else {
            errorMessage = "Permiso de microfono denegado. Activa el permiso en Ajustes."
            permissionGranted = false
            return
        }

        permissionGranted = true
        errorMessage = nil

        // Pre-warm audio session in background
        warmUpAudioSession()
    }

    // MARK: - Pre-warm Audio Session

    private func warmUpAudioSession() {
        guard !isAudioSessionWarmed else { return }
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            isAudioSessionWarmed = true
            // Deactivate immediately after warming — just caches the configuration
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Non-fatal: will retry on actual recording
        }
    }

    // MARK: - Update Locale

    func updateLocale(_ identifier: String) {
        speechLocale = Locale(identifier: identifier)
        speechRecognizer = SFSpeechRecognizer(locale: speechLocale)
    }

    // MARK: - Toggle Recording

    func toggleRecording() async {
        if isRecording {
            stopRecording()
        } else {
            await startRecording()
        }
    }

    // MARK: - Start Recording

    private func startRecording() async {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Reconocimiento de voz no disponible para tu idioma."
            return
        }

        if !permissionGranted {
            await requestPermissions()
            guard permissionGranted else { return }
        }

        // Reset
        transcribedText = ""
        errorMessage = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Error al configurar audio: \(error.localizedDescription)"
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            errorMessage = "Error al crear la solicitud de reconocimiento."
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcribedText = result.bestTranscription.formattedString
                }

                if let error {
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        self.errorMessage = error.localizedDescription
                    }
                    self.stopRecording()
                }
            }
        }

        // Install audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            let channelData = buffer.floatChannelData?[0]
            let frames = buffer.frameLength
            if let channelData, frames > 0 {
                var sum: Float = 0
                for i in 0..<Int(frames) {
                    sum += abs(channelData[i])
                }
                let average = sum / Float(frames)
                Task { @MainActor in
                    self?.audioLevel = min(average * 10, 1.0)
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            errorMessage = "Error al iniciar el motor de audio: \(error.localizedDescription)"
            stopRecording()
        }
    }

    // MARK: - Stop Recording

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        audioLevel = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
