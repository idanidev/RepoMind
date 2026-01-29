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
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var isStopping = false

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    }

    // MARK: - Permissions

    func checkAndRequestPermissions() async {
        // Check current status FIRST — don't re-prompt if already decided
        let currentSpeechStatus = SFSpeechRecognizer.authorizationStatus()

        switch currentSpeechStatus {
        case .authorized:
            break  // Already good
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            guard granted else {
                errorMessage =
                    "Permiso de reconocimiento de voz denegado. Activa el permiso en Ajustes."
                permissionGranted = false
                return
            }
        case .denied, .restricted:
            errorMessage =
                "Permiso de reconocimiento de voz denegado. Activa el permiso en Ajustes."
            permissionGranted = false
            return
        @unknown default:
            errorMessage = "Estado de permisos de voz desconocido."
            permissionGranted = false
            return
        }

        // Check microphone permission
        let micGranted = await checkAndRequestMicPermission()
        guard micGranted else {
            errorMessage = "Permiso de microfono denegado. Activa el permiso en Ajustes."
            permissionGranted = false
            return
        }

        permissionGranted = true
        errorMessage = nil
    }

    // MARK: - Microphone Permission Helper

    private func checkAndRequestMicPermission() async -> Bool {
        if #available(iOS 17, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return true
            case .undetermined: return await AVAudioApplication.requestRecordPermission()
            case .denied: return false
            @unknown default: return false
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: return true
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            case .denied: return false
            @unknown default: return false
            }
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

        // Check authorization status FIRST
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .notDetermined:
            // Only request if we haven't asked before
            await checkAndRequestPermissions()
            guard permissionGranted else { return }
        case .denied, .restricted:
            // If already denied, don't ask again — just show error
            errorMessage = "Permiso de voz denegado. Actívalo en Ajustes."
            return
        case .authorized:
            // Good to go
            break
        @unknown default:
            return
        }

        // Clean up any previous state completely
        cleanupAudioResources()

        // Reset state
        transcribedText = ""
        errorMessage = nil
        isStopping = false

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Error al configurar audio: \(error.localizedDescription)"
            return
        }

        // Create fresh audio engine for each recording session
        let engine = AVAudioEngine()
        self.audioEngine = engine

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.recognitionRequest = request

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) {
            [weak self] result, error in
            Task { @MainActor in
                guard let self, !self.isStopping else { return }

                if let result {
                    self.transcribedText = result.bestTranscription.formattedString
                }

                if let error {
                    let nsError = error as NSError
                    // Ignore "request canceled" (code 216) and "no speech detected" (code 1110)
                    let ignoredCodes = [216, 1110]
                    if nsError.domain == "kAFAssistantErrorDomain"
                        && ignoredCodes.contains(nsError.code)
                    {
                        return
                    }
                    self.errorMessage = error.localizedDescription
                    self.stopRecording()
                }
            }
        }

        // Install audio tap
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak self] buffer, _ in
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
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            errorMessage = "Error al iniciar el motor de audio: \(error.localizedDescription)"
            cleanupAudioResources()
        }
    }

    // MARK: - Stop Recording

    func stopRecording() {
        guard !isStopping else { return }
        isStopping = true

        cleanupAudioResources()

        isRecording = false
        audioLevel = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Cleanup

    private func cleanupAudioResources() {
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil
    }
}
