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

    // Dual-mode per-recognizer buffers — keeps the two languages separate so a
    // wrong-language recognizer can't overwrite good text mid-stream.
    private var primaryTranscript = ""
    private var secondaryTranscript = ""
    private var primaryConfidence: Float = 0
    private var secondaryConfidence: Float = 0
    private var primaryIsFinal = false
    private var secondaryIsFinal = false

    // Silence Detection
    /// Read from `deinit`, which is not guaranteed to run on the main actor. Marked unsafe
    /// deliberately: it is only ever mutated from main-actor code.
    nonisolated(unsafe) private var silenceTimer: Timer?
    private var silenceThreshold: Float = 0.05       // Updated dynamically after calibration
    private let silenceDuration: TimeInterval = 1.5
    private var lastAudioDetectedTime: Date = .now

    // Noise floor calibration
    private var isCalibrating = false
    private var calibrationSamples: [Float] = []
    private let calibrationDuration: TimeInterval = 0.4

    // Contextual strings for domain-specific vocabulary (column names, commands)
    var contextualStrings: [String] = []

    // Track smart routing task for cancellation.
    /// Read from `deinit` — see `silenceTimer` for why this is `nonisolated(unsafe)`.
    nonisolated(unsafe) private var smartRoutingTask: Task<Void, Never>?

    // MARK: - Initialization

    /// No `locale` parameter on purpose: recognition languages always come from the user's system
    /// preferences. The previous initialiser accepted one and silently ignored it, so a test could
    /// pass a locale and assert on behaviour the code never had.
    init() {
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
        // NOT `MainActor.assumeIsolated`. A deinit is not guaranteed to run on the main actor —
        // SwiftUI releases objects while tearing down the view graph, wherever that happens — and
        // assumeIsolated crashes outright when the assumption is wrong. That is the same failure
        // that took down `BiometricAuthManager`. Hand the teardown to the main actor instead of
        // asserting we are already on it.
        let timer = silenceTimer
        let routing = smartRoutingTask
        Task { @MainActor in
            timer?.invalidate()
            routing?.cancel()
        }
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
        isCalibrating = true
        calibrationSamples = []
        primaryTranscript = ""
        secondaryTranscript = ""
        primaryConfidence = 0
        secondaryConfidence = 0
        primaryIsFinal = false
        secondaryIsFinal = false

        #if !os(macOS)
            let audioSession = AVAudioSession.sharedInstance()
            do {
                // Ensure clean state — previous session may still be active.
                try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

                // Try preferred config first; fall back to simpler variants on -50 (paramErr).
                do {
                    try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
                } catch {
                    do {
                        try audioSession.setCategory(.record, mode: .measurement)
                    } catch {
                        try audioSession.setCategory(.record)
                    }
                }
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
            requestPrimary.addsPunctuation = true
            if !contextualStrings.isEmpty {
                requestPrimary.contextualStrings = contextualStrings
            }

            let requestSecondary = SFSpeechAudioBufferRecognitionRequest()
            requestSecondary.shouldReportPartialResults = true
            requestSecondary.addsPunctuation = true
            if !contextualStrings.isEmpty {
                requestSecondary.contextualStrings = contextualStrings
            }

            self.recognitionRequestPrimary = requestPrimary
            self.recognitionRequestSecondary = requestSecondary

            // Task Primary
            recognitionTaskPrimary = recPrimary.recognitionTask(with: requestPrimary) {
                [weak self] result, error in
                self?.handleRecognitionResult(result, error: error, isPrimary: true)
            }

            // Task Secondary
            recognitionTaskSecondary = recSecondary.recognitionTask(with: requestSecondary) {
                [weak self] result, error in
                self?.handleRecognitionResult(result, error: error, isPrimary: false)
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
            if !contextualStrings.isEmpty {
                request.contextualStrings = contextualStrings
            }

            self.recognitionRequest = request

            recognitionTask = speechRecognizer.recognitionTask(with: request) {
                [weak self] result, error in
                self?.handleRecognitionResult(result, error: error, isPrimary: true)
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
            // Silence timer starts after noise-floor calibration completes
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(self.calibrationDuration))
                self.isCalibrating = false
                self.startSilenceTimer()
            }
        } catch {
            errorMessage = String(format: String(localized: "audio_engine_error"), error.localizedDescription)
            cleanupAudioResources()
        }
    }

    private func handleRecognitionResult(
        _ result: SFSpeechRecognitionResult?, error: Error?, isPrimary: Bool
    ) {
        Task { @MainActor in
            guard !self.isStopping else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                guard !text.isEmpty else { return }

                if self.useDualLanguage {
                    // Keep each recognizer's stream separate and let `chooseDualTranscript`
                    // decide which to surface — the secondary language can no longer overwrite
                    // good primary text just because it emitted more (hallucinated) words.
                    let confidence = result.bestTranscription.segments
                        .map(\.confidence).reduce(0, +) / Float(max(result.bestTranscription.segments.count, 1))
                    if isPrimary {
                        self.primaryTranscript = text
                        self.primaryIsFinal = result.isFinal
                        if result.isFinal { self.primaryConfidence = confidence }
                    } else {
                        self.secondaryTranscript = text
                        self.secondaryIsFinal = result.isFinal
                        if result.isFinal { self.secondaryConfidence = confidence }
                    }
                    self.chooseDualTranscript()
                } else {
                    self.transcribedText = text
                    self.processSmartRouting(text: text)
                }

                // Si ya llevamos suficiente silencio cuando llega el texto, parar de inmediato
                let silentSinceLastAudio = Date.now.timeIntervalSince(self.lastAudioDetectedTime)
                if silentSinceLastAudio > self.silenceDuration {
                    self.stopRecording()
                    return
                }
            }

            if let error {
                // Ignore cancellation errors
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain"
                    && [216, 1110].contains(nsError.code)
                {
                    return
                }

                // In dual mode, one recognizer failing is acceptable — the other may still work.
                if self.useDualLanguage && !isPrimary {
                    return
                }

                self.errorMessage = error.localizedDescription
                self.stopRecording()
            }
        }
    }

    /// Decides which of the two recognizers' transcripts to display.
    /// While streaming, the primary language is authoritative (most utterances are in it),
    /// so the secondary can only fill in when the primary has produced nothing yet.
    /// Once both recognizers finalize, the higher-confidence transcript wins.
    private func chooseDualTranscript() {
        let chosen: String
        if primaryIsFinal && secondaryIsFinal {
            chosen = primaryConfidence >= secondaryConfidence ? primaryTranscript : secondaryTranscript
        } else if !primaryTranscript.isEmpty {
            chosen = primaryTranscript
        } else {
            chosen = secondaryTranscript
        }
        guard !chosen.isEmpty else { return }
        transcribedText = chosen
        processSmartRouting(text: chosen)
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
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        // RMS (Root Mean Square) — more perceptually accurate than mean absolute
        var sumSquares: Float = 0
        for i in 0..<frames {
            let sample = channelData[i]
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frames))

        Task { @MainActor in
            if self.isCalibrating {
                // Collect noise floor samples during calibration window
                self.calibrationSamples.append(rms)
                self.audioLevel = 0
            } else {
                if self.calibrationSamples.isEmpty == false {
                    // Set threshold = noise floor median + 40% margin
                    let sorted = self.calibrationSamples.sorted()
                    let median = sorted[sorted.count / 2]
                    self.silenceThreshold = max(median * 1.4, 0.01)
                    self.calibrationSamples = []

                    #if DEBUG
                    print("🎙️ [VoiceManager] Noise floor: \(median), threshold set to: \(self.silenceThreshold)")
                    #endif
                }

                self.audioLevel = min(rms * 15, 1.0)

                if self.audioLevel > self.silenceThreshold {
                    self.lastAudioDetectedTime = .now
                }
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
