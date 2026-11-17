import AVFoundation
import Foundation
import Observation
import Speech

/// Live speech-to-text with Apple's Speech framework (Indian English).
/// Recognition runs on the iPhone when the device supports it, so audio isn't sent anywhere.
/// Listening stops by itself after a short pause, or when the mic is tapped again.
@Observable
final class SpeechRecognizer {
    var transcript = ""
    var isListening = false
    var errorMessage: String?
    var onFinish: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN")) ?? SFSpeechRecognizer()
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var session = 0
    private var forceServer = false      // set after on-device recognition fails, for one retry
    private var startedAt = Date()

    var onDevice: Bool { recognizer?.supportsOnDeviceRecognition == true }

    func toggle() {
        if isListening { finish() } else { Task { await start() } }
    }

    func start() async {
        await MainActor.run { errorMessage = nil }
        let speechStatus = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            await MainActor.run { errorMessage = "Speech Recognition is off for Kosh. Turn it on in Settings → Kosh." }
            return
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard micOK else {
            await MainActor.run { errorMessage = "Microphone is off for Kosh. Turn it on in Settings → Kosh." }
            return
        }
        await MainActor.run { forceServer = false; begin() }
    }

    private func begin() {
        stopAudio()
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Voice recognition isn't available right now. Check your internet, or type instead."
            return
        }
        session += 1
        let mySession = session
        transcript = ""
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.addsPunctuation = false
            let onDeviceNow = recognizer.supportsOnDeviceRecognition && !forceServer
            req.requiresOnDeviceRecognition = onDeviceNow
            req.contextualStrings = ["rupees", "groceries", "Swiggy", "Zomato", "SBI card", "mPokket", "SIP", "auto", "rent", "recharge"]
            request = req

            let eng = AVAudioEngine()
            let input = eng.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                errorMessage = "No microphone found."
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
            eng.prepare()
            try eng.start()
            engine = eng
            isListening = true
            startedAt = Date()

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.session == mySession, self.isListening else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal { self.finish(); return }
                        self.armSilenceTimer(seconds: 2.2)
                    } else if let error {
                        // On-device recognition failed straight away: retry once with Apple's speech service.
                        if onDeviceNow, self.transcript.isEmpty, !self.forceServer {
                            self.forceServer = true
                            self.begin()
                            return
                        }
                        if self.transcript.isEmpty {
                            self.errorMessage = "Didn't catch that. Tap the mic and try again. (\((error as NSError).domain) \((error as NSError).code))"
                        }
                        self.finish()
                    }
                }
            }
            armSilenceTimer(seconds: 7) // nothing said at all
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            stopAudio()
        }
    }

    private func armSilenceTimer(seconds: Double) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.finish()
        }
    }

    func finish() {
        guard isListening else { return }
        let text = transcript
        stopAudio()
        if !text.isEmpty { onFinish?(text) } else if errorMessage == nil { errorMessage = "Didn't catch that. Tap the mic and try again." }
    }

    func cancel() {
        session += 1
        stopAudio()
    }

    private func stopAudio() {
        silenceTimer?.invalidate(); silenceTimer = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
