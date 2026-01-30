import AVFoundation
import Speech
import SwiftUI

// MARK: - Voice Manager (Pro: Silence Detection & Smart Routing)

@MainActor
@Observable
final class VoiceManager {
    // State
    var isRecording = false
    var transcribedText = ""
    var audioLevel: Float = 0
    var errorMessage: String?
    var permissionGranted = false

    // Smart Routing State
    var detectedColumnName: String?

    // Configurable locale
    var speechLocale: Locale = Locale(identifier: "es-ES")

    // Private
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var isStopping = false

    // Silence Detection
    private var silenceTimer: Timer?
    private let silenceThreshold: Float = 0.02
    private let silenceDuration: TimeInterval = 2.0
    private var lastAudioDetectedTime: Date = .now

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    }

    // MARK: - Permissions

    func checkAndRequestPermissions() async {
        let currentSpeechStatus = SFSpeechRecognizer.authorizationStatus()

        switch currentSpeechStatus {
        case .authorized:
            break
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            guard granted else {
                errorMessage = "Permiso denegado. Actívalo en Ajustes."
                permissionGranted = false
                return
            }
        case .denied, .restricted:
            errorMessage = "Permiso denegado. Actívalo en Ajustes."
            permissionGranted = false
            return
        @unknown default:
            permissionGranted = false
            return
        }

        let micGranted = await checkAndRequestMicPermission()
        guard micGranted else {
            errorMessage = "Permiso de micrófono denegado."
            permissionGranted = false
            return
        }

        permissionGranted = true
        errorMessage = nil
    }

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

    // MARK: - Actions

    func toggleRecording() async {
        if isRecording {
            stopRecording()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Reconocimiento no disponible."
            return
        }

        if !permissionGranted {
            await checkAndRequestPermissions()
            guard permissionGranted else { return }
        }

        cleanupAudioResources()

        transcribedText = ""
        errorMessage = nil
        isStopping = false
        detectedColumnName = nil  // Reset smart routing
        lastAudioDetectedTime = .now

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Error audio: \(error.localizedDescription)"
            return
        }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) {
            [weak self] result, error in
            Task { @MainActor in
                guard let self, !self.isStopping else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.transcribedText = text

                    // Smart Routing Logic (Background)
                    self.processSmartRouting(text: text)
                }

                if let error {
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain"
                        && [216, 1110].contains(nsError.code)
                    {
                        return
                    }
                    self.errorMessage = error.localizedDescription
                    self.stopRecording()
                }
            }
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.measureAudioLevel(buffer: buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
            startSilenceTimer()
        } catch {
            errorMessage = "Error inicio motor: \(error.localizedDescription)"
            cleanupAudioResources()
        }
    }

    func stopRecording() {
        guard !isStopping else { return }
        isStopping = true

        stopSilenceTimer()
        cleanupAudioResources()

        isRecording = false
        audioLevel = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Smart Routing (Expert Pattern)

    private func processSmartRouting(text: String) {
        // Run regex in detached task to avoid UI freeze
        Task.detached(priority: .userInitiated) {
            // Pattern: "añadir a [NombreColumna]" at the end
            // Case insensitive
            let pattern = "(?i)\\s+(añadir a|mover a)\\s+(.+)$"

            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    // Group 2 is the column name
                    if let columnRange = Range(match.range(at: 2), in: text) {
                        let columnName = String(text[columnRange])

                        // Extract cleaned text (remove command)
                        let commandRange = Range(match.range(at: 0), in: text)!
                        let cleanText = text.replacingCharacters(in: commandRange, with: "")

                        await MainActor.run {
                            self.transcribedText = cleanText
                            self.detectedColumnName = columnName.trimmingCharacters(
                                in: .whitespacesAndNewlines)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Silence Detection

    private func measureAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = buffer.frameLength

        var sum: Float = 0
        for i in 0..<Int(frames) {
            sum += abs(channelData[i])
        }
        let average = sum / Float(frames)

        Task { @MainActor in
            self.audioLevel = min(average * 10, 1.0)

            if self.audioLevel > self.silenceThreshold {
                self.lastAudioDetectedTime = .now
            }
        }
    }

    private func startSilenceTimer() {
        stopSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isRecording
                    && Date.now.timeIntervalSince(self.lastAudioDetectedTime) > self.silenceDuration
                {
                    // Silence detected -> Auto Stop
                    if !self.transcribedText.isEmpty {
                        self.stopRecording()
                    }
                }
            }
        }
    }

    private func stopSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

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
