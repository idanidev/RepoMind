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

    /// Primary speech locale (first preferred language)
    private(set) var speechLocale: Locale

    /// Secondary speech locale (second preferred language, if different)
    private(set) var secondaryLocale: Locale?

    /// Whether we're using two languages based on user's system settings
    var useDualLanguage: Bool {
        secondaryLocale != nil
    }

    // MARK: - Private State

    private var audioEngine: AVAudioEngine?

    // Single Mode
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?

    // Dual Mode (primary + secondary language)
    private var recognitionRequestPrimary: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionRequestSecondary: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTaskPrimary: SFSpeechRecognitionTask?
    private var recognitionTaskSecondary: SFSpeechRecognitionTask?
    private var speechRecognizerPrimary: SFSpeechRecognizer?
    private var speechRecognizerSecondary: SFSpeechRecognizer?

    private var isStopping = false

    // Silence Detection
    nonisolated(unsafe) private var silenceTimer: Timer?
    private let silenceThreshold: Float = 0.02
    private let silenceDuration: TimeInterval = 2.0
    private var lastAudioDetectedTime: Date = .now

    // ✅ FIX: Track smart routing task for cancellation
    nonisolated(unsafe) private var smartRoutingTask: Task<Void, Never>?

    // MARK: - Initialization

    init(locale: Locale = .current) {
        // Automatically detect languages from user's system preferences
        let (primary, secondary) = Self.resolveSystemLanguages()
        self.speechLocale = primary
        self.secondaryLocale = secondary
        self.speechRecognizer = SFSpeechRecognizer(locale: primary)
        configureRecognizers()

        #if DEBUG
            print(
                "🎙️ [VoiceManager] Primary: \(primary.identifier), Secondary: \(secondary?.identifier ?? "none")"
            )
        #endif
    }

    /// Resolves the user's preferred languages from system settings.
    /// Returns primary locale and optional secondary locale if user has multiple languages configured.
    private static func resolveSystemLanguages() -> (primary: Locale, secondary: Locale?) {
        let preferredLanguages = Locale.preferredLanguages

        // Get primary language
        let primaryLang = preferredLanguages.first ?? "es"
        let primary = mapToSpeechLocale(languageCode: primaryLang)

        // Check if user has a second language configured that's different
        var secondary: Locale? = nil
        if preferredLanguages.count > 1 {
            let secondaryLang = preferredLanguages[1]
            let secondaryLocale = mapToSpeechLocale(languageCode: secondaryLang)

            // Only use secondary if it's a different language family
            let primaryFamily = primary.language.languageCode?.identifier
            let secondaryFamily = secondaryLocale.language.languageCode?.identifier

            if primaryFamily != secondaryFamily {
                secondary = secondaryLocale
            }
        }

        return (primary, secondary)
    }

    /// Maps a language identifier to a speech-compatible locale
    private static func mapToSpeechLocale(languageCode: String) -> Locale {
        let lang =
            Locale(identifier: languageCode).language.languageCode?.identifier
            ?? languageCode.prefix(2).lowercased()

        switch lang {
        case "es": return Locale(identifier: "es-ES")
        case "en": return Locale(identifier: "en-US")
        case "ca": return Locale(identifier: "ca-ES")
        case "gl": return Locale(identifier: "gl-ES")
        case "eu": return Locale(identifier: "eu-ES")
        case "pt": return Locale(identifier: "pt-BR")
        case "fr": return Locale(identifier: "fr-FR")
        case "de": return Locale(identifier: "de-DE")
        case "it": return Locale(identifier: "it-IT")
        case "ja": return Locale(identifier: "ja-JP")
        case "zh": return Locale(identifier: "zh-CN")
        case "ko": return Locale(identifier: "ko-KR")
        case "nl": return Locale(identifier: "nl-NL")
        case "ru": return Locale(identifier: "ru-RU")
        case "ar": return Locale(identifier: "ar-SA")
        default: return Locale(identifier: "\(lang)-\(lang.uppercased())")
        }
    }

    // ✅ FIX: Explicit cleanup before deallocation to prevent
    // TaskLocal/malloc crash when smartRoutingTask outlives the object.
    deinit {
        silenceTimer?.invalidate()
        smartRoutingTask?.cancel()
    }

    private func configureRecognizers() {
        if let secondary = secondaryLocale {
            // Dual mode: use both primary and secondary languages
            speechRecognizerPrimary = SFSpeechRecognizer(locale: speechLocale)
            speechRecognizerSecondary = SFSpeechRecognizer(locale: secondary)
        } else {
            // Single mode: just the primary language
            speechRecognizer = SFSpeechRecognizer(locale: speechLocale)
        }
    }

    // MARK: - Permissions

    func checkAndRequestPermissions() async {
        let currentSpeechStatus = SFSpeechRecognizer.authorizationStatus()

        switch currentSpeechStatus {
        case .authorized:
            // Already granted speech — we will check mic in startRecording when actually needed
            // to avoid showing the mic dialog on app startup/repo switch.
            permissionGranted = true
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            guard granted else {
                errorMessage = String(localized: "permission_denied_settings")
                permissionGranted = false
                return
            }
        case .denied, .restricted:
            errorMessage = String(localized: "permission_denied_settings")
            permissionGranted = false
            return
        @unknown default:
            permissionGranted = false
            return
        }

        // Do not request mic here, doing it on load triggers unwanted dialogs.
        // It will be requested in `startRecording()` when the user actually clicks the mic.

        permissionGranted = true
        errorMessage = nil
    }

    private func checkAndRequestMicPermission() async -> Bool {
        if #available(iOS 17, macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return true
            case .undetermined: return await AVAudioApplication.requestRecordPermission()
            case .denied: return false
            @unknown default: return false
            }
        } else {
            #if !os(macOS)
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
            #else
                return false  // On older macOS, mic permission is handled differently, 14.0+ handled above
            #endif
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
        if !permissionGranted {
            await checkAndRequestPermissions()
            guard permissionGranted else { return }
        }

        // Only request mic permission right before recording, to avoid showing dialog at startup
        let micGranted = await checkAndRequestMicPermission()
        guard micGranted else {
            errorMessage = String(localized: "mic_permission_denied")
            permissionGranted = false
            return
        }

        cleanupAudioResources()

        #if DEBUG
            print(
                "🎙️ [VoiceManager] speechLocale: \(speechLocale.identifier), dualMode: \(useDualLanguage)"
            )
            print(
                "🎙️ [VoiceManager] Locale.current: \(Locale.current.identifier), preferred: \(Locale.preferredLanguages.first ?? "nil")"
            )
        #endif

        transcribedText = ""
        errorMessage = nil
        isStopping = false
        detectedColumnName = nil
        lastAudioDetectedTime = .now

        #if !os(macOS)
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                errorMessage = String(format: String(localized: "audio_error"), error.localizedDescription)
                return
            }
        #endif

        let engine = AVAudioEngine()
        self.audioEngine = engine

        if useDualLanguage {
            // DUAL MODE: Use primary + secondary languages from system settings
            guard let recPrimary = speechRecognizerPrimary,
                let recSecondary = speechRecognizerSecondary,
                recPrimary.isAvailable, recSecondary.isAvailable
            else {
                errorMessage = String(localized: "dual_recognition_unavailable")
                return
            }

            // Create SEPARATE requests for each language
            let requestPrimary = SFSpeechAudioBufferRecognitionRequest()
            requestPrimary.shouldReportPartialResults = true

            let requestSecondary = SFSpeechAudioBufferRecognitionRequest()
            requestSecondary.shouldReportPartialResults = true

            if #available(iOS 17, *) {
                if recPrimary.supportsOnDeviceRecognition {
                    requestPrimary.requiresOnDeviceRecognition = true
                }
                if recSecondary.supportsOnDeviceRecognition {
                    requestSecondary.requiresOnDeviceRecognition = true
                }
            }

            self.recognitionRequestPrimary = requestPrimary
            self.recognitionRequestSecondary = requestSecondary

            // Task Primary
            recognitionTaskPrimary = recPrimary.recognitionTask(with: requestPrimary) {
                [weak self] result, error in
                self?.handleRecognitionResult(result, error: error)
            }

            // Task Secondary
            recognitionTaskSecondary = recSecondary.recognitionTask(with: requestSecondary) {
                [weak self] result, error in
                self?.handleRecognitionResult(result, error: error)
            }

        } else {
            // SINGLE MODE logic
            guard let speechRecognizer, speechRecognizer.isAvailable else {
                errorMessage = String(localized: "recognition_unavailable")
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true

            if #available(iOS 17, *), speechRecognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            self.recognitionRequest = request

            recognitionTask = speechRecognizer.recognitionTask(with: request) {
                [weak self] result, error in
                self?.handleRecognitionResult(result, error: error)
            }
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let isDual = useDualLanguage

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak self] buffer, _ in
            guard let self else { return }

            if isDual {
                self.recognitionRequestPrimary?.append(buffer)
                self.recognitionRequestSecondary?.append(buffer)
            } else {
                self.recognitionRequest?.append(buffer)
            }

            self.measureAudioLevel(buffer: buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
            startSilenceTimer()
        } catch {
            errorMessage = String(format: String(localized: "audio_engine_error"), error.localizedDescription)
            cleanupAudioResources()
        }
    }

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        Task { @MainActor in
            guard !self.isStopping else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                // Update text from whichever recognizer triggers first/most recently
                self.transcribedText = text
                self.processSmartRouting(text: text)
            }

            if let error {
                // Ignore cancellation errors
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain"
                    && [216, 1110].contains(nsError.code)
                {
                    return
                }

                // In dual mode, one might fail while other works.
                // However, for simplicity, we report and stop on error.
                self.errorMessage = error.localizedDescription
                self.stopRecording()
            }
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

        #if !os(macOS)
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Smart Routing

    func switchLocale() {
        // Only active in Single Mode
        guard !useDualLanguage else { return }

        let currentId = speechLocale.identifier
        if currentId.starts(with: "es") {
            speechLocale = Locale(identifier: "en-US")
        } else {
            speechLocale = Locale(identifier: "es-ES")
        }
    }

    private func processSmartRouting(text: String) {
        // Cancel previous task before starting new one
        smartRoutingTask?.cancel()

        smartRoutingTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard !Task.isCancelled else { return }

            // Support both Spanish and English commands in regex
            let pattern = "(?i)\\s+(añadir a|mover a|add to|move to)\\s+(.+)$"

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
                // If we detected a valid command, stop recording immediately (success!)
                self?.stopRecording()
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

        recognitionRequestPrimary?.endAudio()
        recognitionRequestPrimary = nil
        recognitionRequestSecondary?.endAudio()
        recognitionRequestSecondary = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionTaskPrimary?.cancel()
        recognitionTaskPrimary = nil
        recognitionTaskSecondary?.cancel()
        recognitionTaskSecondary = nil
    }
}
