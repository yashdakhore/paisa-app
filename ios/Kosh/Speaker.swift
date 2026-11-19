import AVFoundation

/// Reads Kosh's answers aloud in an Indian English voice.
@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()

    func say(_ text: String) {
        stop()
        // "₹1,200" → "1,200 rupees", "−" → "minus"
        var t = text.replacingOccurrences(of: "₹([0-9,]+)", with: "$1 rupees", options: .regularExpression)
        t = t.replacingOccurrences(of: "−", with: "minus ")
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: t)
        u.voice = AVSpeechSynthesisVoice(language: "en-IN") ?? AVSpeechSynthesisVoice(language: "en-GB")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        synth.speak(u)
    }

    func stop() { if synth.isSpeaking { synth.stopSpeaking(at: .immediate) } }
}
