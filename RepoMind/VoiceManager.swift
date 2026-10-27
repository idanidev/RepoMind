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

    /// What may follow "añadir a" / "move to": the board's columns, or the apps outside a board. A
    /// command is only a command when it names one of these; any other sentence that happens to contain
    /// "add to" ("arreglar el botón de añadir a favoritos") used to be cut there and the recording
    /// stopped mid-sentence.
    var routingNames: [String] = []

    // MARK: - Configuration

    /// Primary speech locale (first preferred language)
    private(set) var speechLocale: Locale

    /// Secondary speech locale (second preferred language, if different)
    private(set) var secondaryLocale: Locale?

    /// Whether we're using two languages based on user's system settings, and both have a recognizer.
    /// A language the recognizer does not support (the locale map builds guesses like "sv-SV" for
    /// languages it does not know) used to leave this true with no recognizer behind it, and every
    /// recording failed with "dual recognition unavailable".
    private(set) var useDualLanguage = false

    /// Whether the recording in progress runs both recognizers. It starts out as `useDualLanguage`, and
    /// falls back to the first language alone when the second one is not available right now.
    private var dualThisRecording = false

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
    /// True from the stop until the recognizer has said its last word. The engine and the timers are
    /// off and the request is closed, but `isRecording` stays up so whoever reads the transcript waits
    /// for it; it is what stops the last words of every recording ended by the button from being lost.
    private(set) var isFinishing = false
    private var finishTask: Task<Void, Never>?
    /// How long to wait for that last result after the audio ends. It normally arrives within a
    /// fraction of a second; this is the limit for when it does not.
    private static let finalResultGrace = 1_000

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
    /// Seconds of silence that stop a recording. Settings → Voice; 0 means only the button
    /// stops it. 1.5 s cut people off mid-thought, so the default is 3.
    private var silenceDuration: TimeInterval {
        UserDefaults.standard.object(forKey: "voiceSilenceSeconds") as? Double ?? 3
    }
    private var lastAudioDetectedTime: Date = .now

    // Noise floor calibration
    private var isCalibrating = false
    private var calibrationSamples: [Float] = []
    private static let calibrationDuration: TimeInterval = 0.4
    private var calibrationTask: Task<Void, Never>?

    /// Apple's speech recognizer refuses audio past roughly a minute and then fails the whole
    /// request, losing everything said. Stopping cleanly just before that keeps the transcript.
    private static let maxRecordingDuration: TimeInterval = 55
    private var maxDurationTask: Task<Void, Never>?

    /// Set when recording is cut short by the system — a phone call, or headphones being pulled
    /// out. Without this the engine died and the button simply stayed lit, recording nothing.
    private var interruptionObservers: [NSObjectProtocol] = []

    // Contextual strings for domain-specific vocabulary (column names, commands)
    var contextualStrings: [String] = []

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

    // ✅ FIX: Explicit cleanup before deallocation, so a repeating timer does not outlive the object.
    deinit {
        // NOT `MainActor.assumeIsolated`. A deinit is not guaranteed to run on the main actor —
        // SwiftUI releases objects while tearing down the view graph, wherever that happens — and
        // assumeIsolated crashes outright when the assumption is wrong. That is the same failure
        // that took down `BiometricAuthManager`. Hand the teardown to the main actor instead of
        // asserting we are already on it.
        let timer = silenceTimer
        Task { @MainActor in
            timer?.invalidate()
        }
    }

    /// One place to build a request, so the single- and dual-language paths cannot drift apart.
    ///
    /// `taskHint = .dictation` is the part that matters: the default, `.unspecified`, makes the
    /// recognizer hedge between short commands and free speech. These are dictated notes — often
    /// long, unstructured sentences — and telling it so measurably reduces invented words.
    ///
    /// On the device whenever the recognizer can: what is dictated names private repos and customers,
    /// and the default sends the audio and the vocabulary (`contextualStrings`) to Apple's servers.
    /// A language without an on-device model still falls back to the server, as it always did.
    private func makeRecognitionRequest(for recognizer: SFSpeechRecognizer?) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        if !contextualStrings.isEmpty {
            request.contextualStrings = contextualStrings
        }
        return request
    }

    private func configureRecognizers(allowDual: Bool = true) {
        if allowDual, let secondary = secondaryLocale,
           let primaryRecognizer = SFSpeechRecognizer(locale: speechLocale),
           let secondaryRecognizer = SFSpeechRecognizer(locale: secondary) {
            // Dual mode: use both primary and secondary languages
            speechRecognizerPrimary = primaryRecognizer
            speechRecognizerSecondary = secondaryRecognizer
            speechRecognizer = nil
            useDualLanguage = true
        } else {
            // Single mode: just the primary language, which is also where a second language the
            // recognizer cannot handle ends up.
            speechRecognizerPrimary = nil
            speechRecognizerSecondary = nil
            speechRecognizer = SFSpeechRecognizer(locale: speechLocale)
            useDualLanguage = false
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

        // A recording started while the previous one was still finishing, or twice in a row, left the
        // first one's timers running: the second recording was cut at 55 s counted from the first.
        finishTask?.cancel()
        finishTask = nil
        isFinishing = false
        stopSilenceTimer()
        calibrationTask?.cancel()
        calibrationTask = nil
        maxDurationTask?.cancel()
        maxDurationTask = nil
        cleanupAudioResources()

        // Both recognizers or, when the second language is not available right now, only the first.
        dualThisRecording = useDualLanguage
            && speechRecognizerPrimary?.isAvailable == true && speechRecognizerSecondary?.isAvailable == true

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

                // `.record` + `.measurement`, and deliberately WITHOUT `.allowBluetooth`.
                //
                // The previous config asked for `.playAndRecord` with `.allowBluetooth`. Bluetooth
                // input on iOS means the HFP profile, which is 8–16 kHz mono built for phone calls:
                // when AirPods are connected, the microphone silently drops to call quality and the
                // recognizer starts inventing words. Leaving the option out keeps recording on the
                // device mic even with headphones connected, which is what dictation wants.
                //
                // `.measurement` also disables the system's input processing (AGC, EQ), which is
                // what Apple recommends for speech recognition — that processing is tuned for
                // calls, not transcription.
                do {
                    try audioSession.setCategory(.record, mode: .measurement)
                } catch {
                    try audioSession.setCategory(.record)
                }
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                errorMessage = String(format: String(localized: "audio_error"), error.localizedDescription)
                return
            }
        #endif

        let engine = AVAudioEngine()
        self.audioEngine = engine

        if dualThisRecording {
            // DUAL MODE: Use primary + secondary languages from system settings
            guard let recPrimary = speechRecognizerPrimary, let recSecondary = speechRecognizerSecondary else {
                errorMessage = String(localized: "dual_recognition_unavailable")
                deactivateAudioSession()
                return
            }

            // Create SEPARATE requests for each language
            let requestPrimary = makeRecognitionRequest(for: recPrimary)
            let requestSecondary = makeRecognitionRequest(for: recSecondary)

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
            // SINGLE MODE logic. In a dual configuration whose second language is down, the first one.
            guard let recognizer = speechRecognizer ?? speechRecognizerPrimary, recognizer.isAvailable else {
                errorMessage = String(localized: "recognition_unavailable")
                deactivateAudioSession()
                return
            }

            let request = makeRecognitionRequest(for: recognizer)
            self.recognitionRequest = request

            recognitionTask = recognizer.recognitionTask(with: request) {
                [weak self] result, error in
                self?.handleRecognitionResult(result, error: error, isPrimary: true)
            }
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let isDual = dualThisRecording

        // A hardware format of 0 Hz means the input route is not ready — it happens when the
        // session was just activated, or when headphones are being swapped. `installTap` throws an
        // uncatchable Objective-C exception on that, so the app died instead of showing an error.
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            errorMessage = String(localized: "audio_input_unavailable")
            cleanupAudioResources()
            deactivateAudioSession()
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak self] buffer, _ in
            // Once the stop has begun the requests are closed (`endAudio`), and a buffer that was
            // already on its way must not be appended to them.
            guard let self, !self.isStopping else { return }

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
            // Silence timer starts after noise-floor calibration completes. Held onto so stopping
            // within the calibration window cancels it — otherwise it fired after the fact and
            // started a repeating timer that `stopRecording` had already finished cleaning up,
            // leaving it running for the rest of the app's life.
            calibrationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.calibrationDuration))
                guard let self, !Task.isCancelled, self.isRecording else { return }
                self.isCalibrating = false
                self.startSilenceTimer()
            }

            maxDurationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.maxRecordingDuration))
                guard let self, !Task.isCancelled, self.isRecording else { return }
                self.stopRecording()
            }

            observeAudioInterruptions()
        } catch {
            errorMessage = String(format: String(localized: "audio_engine_error"), error.localizedDescription)
            cleanupAudioResources()
            deactivateAudioSession()
        }
    }

    private func handleRecognitionResult(
        _ result: SFSpeechRecognitionResult?, error: Error?, isPrimary: Bool
    ) {
        Task { @MainActor in
            // After the stop the recognizer still gets a moment to say its last words: those results
            // are kept, everything else is ignored.
            guard !self.isStopping || self.isFinishing else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                guard !text.isEmpty else { return }

                if self.dualThisRecording {
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

                if self.isFinishing {
                    // The last words are in once every recognizer in use has finalized.
                    let allFinal = self.dualThisRecording
                        ? (self.primaryIsFinal && self.secondaryIsFinal) : result.isFinal
                    if allFinal { self.finishStop() }
                    return
                }

                // Si ya llevamos suficiente silencio cuando llega el texto, parar de inmediato
                let silentSinceLastAudio = Date.now.timeIntervalSince(self.lastAudioDetectedTime)
                if self.silenceDuration > 0, silentSinceLastAudio > self.silenceDuration {
                    self.stopRecording()
                    return
                }
            }

            if let error {
                // A task that fails while the last words are awaited has nothing more to say.
                if self.isFinishing {
                    self.finishStop()
                    return
                }

                // Cancellation, or the recognizer ending its task on its own (nothing heard for a
                // while). Nothing more can come from that task, yet the microphone went on until the
                // one-minute cap, with "Listening…" on screen and nothing being transcribed.
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain"
                    && [216, 1110].contains(nsError.code)
                {
                    if !self.dualThisRecording { self.stopRecording(immediately: true) }
                    return
                }

                // In dual mode, one recognizer failing is acceptable — the other may still work.
                if self.dualThisRecording && !isPrimary {
                    return
                }

                self.errorMessage = error.localizedDescription
                self.stopRecording(immediately: true)
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

    /// Stops listening. With `immediately` false (the default) the recognizer gets a moment to report
    /// its last words, and `isRecording` goes down when it has, or after `finalResultGrace`.
    func stopRecording(immediately: Bool = false) {
        guard !isStopping else { return }
        isStopping = true

        stopSilenceTimer()
        calibrationTask?.cancel()
        calibrationTask = nil
        maxDurationTask?.cancel()
        maxDurationTask = nil
        removeInterruptionObservers()
        audioLevel = 0
        closeAudioInput()

        let hasRecognition = recognitionTask != nil || recognitionTaskPrimary != nil || recognitionTaskSecondary != nil
        guard !immediately, hasRecognition else {
            finishStop()
            return
        }

        // After `endAudio` the recognizer delivers a final result within a moment. Cancelling at once,
        // as this used to, threw away whatever it had not yet reported as a partial: the last word or
        // two of every recording that was ended by the button.
        isFinishing = true
        finishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.finalResultGrace))
            guard !Task.isCancelled else { return }
            self?.finishStop()
        }
    }

    private func finishStop() {
        finishTask?.cancel()
        finishTask = nil
        isFinishing = false
        cancelRecognition()
        isRecording = false
        deactivateAudioSession()
    }

    private func deactivateAudioSession() {
        #if !os(macOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Interruptions

    /// Stops cleanly when the system takes the microphone away.
    ///
    /// A phone call, Siri, or unplugging headphones tears the audio engine down underneath us.
    /// Nothing was listening for it, so `isRecording` stayed true: the button kept pulsing, the
    /// waveform froze, and every further word was lost with no indication anything had happened.
    private func observeAudioInterruptions() {
        #if !os(macOS)
            removeInterruptionObservers()
            let center = NotificationCenter.default

            let interruption = center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(), queue: .main
            ) { [weak self] note in
                guard
                    let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                    AVAudioSession.InterruptionType(rawValue: raw) == .began
                else { return }
                MainActor.assumeIsolated {
                    guard let self, self.isRecording else { return }
                    self.errorMessage = String(localized: "voice_interrupted")
                    self.stopRecording()
                }
            }

            let route = center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(), queue: .main
            ) { [weak self] note in
                guard
                    let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                    let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                    reason == .oldDeviceUnavailable
                else { return }
                MainActor.assumeIsolated {
                    guard let self, self.isRecording else { return }
                    self.errorMessage = String(localized: "voice_input_changed")
                    self.stopRecording()
                }
            }

            // A route change that is not the old device leaving (headphones plugged in, Bluetooth
            // connecting) stops the engine too, and `isRecording` stayed true with a dead engine until
            // the one-minute cap.
            let configuration = center.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isRecording, !self.isStopping else { return }
                    self.errorMessage = String(localized: "voice_input_changed")
                    self.stopRecording()
                }
            }

            interruptionObservers = [interruption, route, configuration]
        #endif
    }

    private func removeInterruptionObservers() {
        interruptionObservers.forEach(NotificationCenter.default.removeObserver)
        interruptionObservers = []
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

        // Without this the button was decorative: it swapped the label and the stored locale, but
        // `speechRecognizer` was still the object built for the previous language in `init`, so
        // recognition carried on in the language you had just switched away from.
        configureRecognizers(allowDual: false)
    }

    private func processSmartRouting(text: String) {
        guard !routingNames.isEmpty, let found = Self.routing(in: text, names: routingNames) else { return }
        transcribedText = found.text
        detectedColumnName = found.name
        // A command at the end of the sentence is how a dictation says "that is all".
        stopRecording()
    }

    /// "… añadir a Hecho" → the dictation without the command, and the name it asked for.
    ///
    /// Nil unless what follows the command is one of `names`, whole, and something precedes it. The
    /// pattern used to take any "add to" in the sentence: "arreglar el botón de añadir a favoritos" was
    /// cut at "de", "favoritos" became a column that does not exist, and the recording stopped
    /// mid-sentence. The last command that names something wins, so "add to cart, move to Done" is
    /// about Done.
    nonisolated static func routing(in text: String, names: [String]) -> (text: String, name: String)? {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\s(?:añadir a|mover a|add to|move to)\\s+")
        else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: whole).reversed() {
            guard let command = Range(match.range, in: text) else { continue }
            let spoken = normalizedName(String(text[command.upperBound...]))
            guard !spoken.isEmpty, let name = names.first(where: { normalizedName($0) == spoken }) else { continue }
            let before = text[..<command.lowerBound]
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-–")))
            guard !before.isEmpty else { continue }
            return (before, name)
        }
        return nil
    }

    /// Without case, accents or the punctuation the recognizer adds around the last words.
    nonisolated private static func normalizedName(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
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

                // `audioLevel` is a display value for the pulsing button: raw RMS is tiny, so it is
                // scaled ×15 to fill the 0–1 range. The threshold, though, is calibrated from *raw*
                // RMS. Comparing the scaled value against it made the test roughly 15× too easy to
                // pass, so almost any room noise counted as speech, `lastAudioDetectedTime` kept
                // resetting, and the silence auto-stop effectively never fired.
                self.audioLevel = min(rms * 15, 1.0)

                if rms > self.silenceThreshold {
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
                let pause = self.silenceDuration
                if pause > 0, silentDuration > pause, !self.transcribedText.isEmpty {
                    self.stopRecording()
                }
            }
        }
    }

    private func stopSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    /// Stops listening: the engine and its tap off, and the requests told that no more audio is coming.
    /// The recognition tasks are left alone so that what they still have to say can arrive.
    private func closeAudioInput() {
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequestPrimary?.endAudio()
        recognitionRequestSecondary?.endAudio()
    }

    private func cancelRecognition() {
        recognitionRequest = nil
        recognitionRequestPrimary = nil
        recognitionRequestSecondary = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionTaskPrimary?.cancel()
        recognitionTaskPrimary = nil
        recognitionTaskSecondary?.cancel()
        recognitionTaskSecondary = nil
    }

    private func cleanupAudioResources() {
        closeAudioInput()
        cancelRecognition()
    }
}
