import AVFoundation
import Speech
import SwiftUI

// MARK: - Voice Manager

@MainActor
@Observable
final class VoiceManager {
    // MARK: - Public State

    var isRecording = false
    var transcribedText = ""
    var audioLevel: Float = 0
    var errorMessage: String?
    var permissionGranted = false
    var detectedColumnName: String?

    // MARK: - Configuration

    // ✅ FIX: Configurable locale (defaults to device locale)
    var speechLocale: Locale {
        didSet {
            speechRecognizer = SFSpeechRecognizer(locale: speechLocale)
        }
    }

    // MARK: - Private State

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

    // ✅ FIX: Track smart routing task for cancellation
    private var smartRoutingTask: Task<Void, Never>?

    // MARK: - Initialization

    init(locale: Locale = .current) {
        self.speechLocale = locale
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
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
                errorMessage = String(localized: "Permiso denegado. Actívalo en Ajustes.")
                permissionGranted = false
                return
            }
        case .denied, .restricted:
            errorMessage = String(localized: "Permiso denegado. Actívalo en Ajustes.")
            permissionGranted = false
            return
        @unknown default:
            permissionGranted = false
            return
        }

        let micGranted = await checkAndRequestMicPermission()
        guard micGranted else {
            errorMessage = String(localized: "Permiso de micrófono denegado.")
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

    // MARK: - Recording Actions

    func toggleRecording() async {
        if isRecording {
            stopRecording()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = String(localized: "Reconocimiento no disponible.")
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
        detectedColumnName = nil
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

        // ✅ FIX: Use on-device recognition when available (iOS 17+)
        if #available(iOS 17, *), speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        self.recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) {
            [weak self] result, error in
            Task { @MainActor in
                guard let self, !self.isStopping else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.transcribedText = text
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
        // ✅ FIX: Cancel smart routing task
        smartRoutingTask?.cancel()
        smartRoutingTask = nil

        cleanupAudioResources()

        isRecording = false
        audioLevel = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Smart Routing

    private func processSmartRouting(text: String) {
        // ✅ FIX: Cancel previous task before starting new one
        smartRoutingTask?.cancel()

        smartRoutingTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard !Task.isCancelled else { return }

            let pattern = "(?i)\\s+(añadir a|mover a)\\s+(.+)$"

            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else { return }

            guard !Task.isCancelled else { return }

            guard let columnRange = Range(match.range(at: 2), in: text),
                let commandRange = Range(match.range(at: 0), in: text)
            else { return }

            let columnName = String(text[columnRange])
            let cleanText = text.replacingCharacters(in: commandRange, with: "")

            await MainActor.run { [weak self] in
                guard !Task.isCancelled else { return }
                self?.transcribedText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.detectedColumnName = columnName.trimmingCharacters(
                    in: .whitespacesAndNewlines)
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
                guard let self, self.isRecording else { return }

                let silentDuration = Date.now.timeIntervalSince(self.lastAudioDetectedTime)
                if silentDuration > self.silenceDuration && !self.transcribedText.isEmpty {
                    self.stopRecording()
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
