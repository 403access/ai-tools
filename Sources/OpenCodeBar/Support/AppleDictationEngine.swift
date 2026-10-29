import AVFoundation
import Foundation
import Speech

/// System speech recognition (`SFSpeechRecognizer`).
///
/// Kept as the fallback for machines where the local Parakeet model cannot be
/// prepared — no network on first use, or a model download that fails. It is
/// the older, less accurate engine, but it always works once permissions are
/// granted.
@MainActor
final class AppleDictationEngine: DictationEngine {
    var onTranscript: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var capture: MicrophoneCapture?
    private var latest = ""

    func prepare(reportProgress: @escaping (Double, String) -> Void) async throws {
        try await requestAccess()
    }

    func startCapture() async throws {
        guard let recognizer = makeRecognizer(), recognizer.isAvailable else {
            throw DictationFailure(message: "Speech recognition isn't available right now.")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let capture = MicrophoneCapture()
        do {
            try capture.start { [weak request] buffer in
                request?.append(buffer)
            }
        } catch {
            throw DictationFailure(message: message(for: error))
        }

        self.capture = capture
        self.recognizer = recognizer
        self.request = request
        self.latest = ""

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handle(result: result, error: error)
            }
        }
    }

    func finish() async -> String {
        capture?.stop()
        capture = nil
        request?.endAudio()
        task?.finish()

        // Give the recognizer a moment to deliver the last words. The system
        // service usually answers well inside this window.
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        let final = latest
        reset()
        return final
    }

    func cancel() async {
        reset()
    }

    // MARK: - Recognition

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let spoken = result.bestTranscription.formattedString
            latest = spoken
            onTranscript?(spoken)
            if result.isFinal {
                reset()
                return
            }
        }

        if let error {
            // Errors after an explicit stop are expected while finalizing.
            if capture != nil {
                onFailure?(message(for: error))
            }
            reset()
        }
    }

    private func makeRecognizer() -> SFSpeechRecognizer? {
        let locale = Locale.preferredLanguages.first.map { Locale(identifier: $0) } ?? Locale.current
        return SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    }

    // MARK: - Permission

    private func requestAccess() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            break
        case .notDetermined:
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
            guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
                throw DictationFailure(
                    message: "Speech recognition is turned off. Allow it in Settings to dictate prompts."
                )
            }
        case .denied, .restricted:
            throw DictationFailure(
                message: "Speech recognition is turned off. Allow it in Settings to dictate prompts."
            )
        @unknown default:
            throw DictationFailure(message: "Speech recognition isn't available on this device.")
        }

        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard microphoneGranted else {
            throw DictationFailure(
                message: "Microphone access is turned off. Allow it in Settings to dictate prompts."
            )
        }
    }

    // MARK: - Teardown

    private func reset() {
        capture?.stop()
        capture = nil
        task?.cancel()
        request?.endAudio()
        request = nil
        task = nil
        recognizer = nil
        latest = ""
    }

    private func message(for error: Error) -> String {
        if (error as NSError).domain == "kAFAssistantErrorDomain" {
            return "Dictation stopped. Tap the microphone to try again."
        }
        return error.localizedDescription
    }
}
