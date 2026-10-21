import AVFoundation
import Speech
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Live speech-to-text for the prompt composers.
///
/// Wraps `SFSpeechRecognizer` and `AVAudioEngine` in a small state machine:
/// request permission, stream microphone buffers, and publish the growing
/// transcript while the user speaks. On-device recognition is preferred when
/// the current locale supports it, so prompts stay on the device.
@MainActor
final class SpeechDictation: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isPreparing = false
    @Published var errorMessage: String?

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var baseText = ""
    private var update: ((String) -> Void)?
    private var isFinalizing = false

    /// Starts or stops dictation. `update` receives the draft with the live
    /// transcript appended to whatever was already in the field.
    func toggle(text: String, update: @escaping (String) -> Void) async {
        if isListening || isPreparing {
            stop()
        } else {
            await start(text: text, update: update)
        }
    }

    func start(text: String, update: @escaping (String) -> Void) async {
        guard !isListening, !isPreparing else { return }
        // Drop a previous task that is still finalizing so it cannot feed
        // results into the new dictation session.
        if isFinalizing || task != nil { reset() }

        errorMessage = nil
        isPreparing = true
        baseText = text
        self.update = update
        defer { isPreparing = false }

        guard await requestAccess() else {
            self.update = nil
            baseText = ""
            return
        }

        // The view may have disappeared while the permission sheet was open.
        guard isPreparing, self.update != nil else { return }

        guard let recognizer = makeRecognizer(), recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            self.update = nil
            baseText = ""
            return
        }

        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw DictationError.noMicrophone
            }

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()

            self.recognizer = recognizer
            self.audioEngine = engine
            self.request = request
            isListening = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    self?.handle(result: result, error: error)
                }
            }
        } catch {
            errorMessage = message(for: error)
            reset()
        }
    }

    /// Stops listening and lets the recognizer finalize the last words.
    func stop() {
        guard isListening else { return }

        isListening = false
        isFinalizing = true
        audioEngine?.stop()
        request?.endAudio()
        task?.finish()

        // Keep the audio session briefly so a final transcription can land,
        // then release everything even if the recognizer stays quiet.
        let finishingTask = task
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, self.task === finishingTask else { return }
            self.reset()
        }
    }

    /// Stops immediately, discarding any late recognition callbacks.
    func cancel() {
        guard isListening || isPreparing || task != nil else { return }
        update = nil
        baseText = ""
        reset()
    }

    // MARK: - Recognition

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        guard isListening || isFinalizing else { return }

        if let result {
            let spoken = result.bestTranscription.formattedString
            update?(joined(baseText, spoken))
            if result.isFinal {
                reset()
                return
            }
        }

        if let error {
            // Errors after an explicit stop are expected while finalizing.
            if isListening {
                errorMessage = message(for: error)
            }
            reset()
        }
    }

    private func joined(_ base: String, _ spoken: String) -> String {
        guard !spoken.isEmpty else { return base }
        guard !base.isEmpty else { return spoken }
        if base.hasSuffix(" ") || base.hasSuffix("\n") { return base + spoken }
        return base + " " + spoken
    }

    private func makeRecognizer() -> SFSpeechRecognizer? {
        let locale = Locale.preferredLanguages.first.map { Locale(identifier: $0) } ?? Locale.current
        return SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    }

    // MARK: - Permission

    private func requestAccess() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            break
        case .notDetermined:
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
            guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
                errorMessage = "Speech recognition is turned off. Allow it in Settings to dictate prompts."
                return false
            }
        case .denied, .restricted:
            errorMessage = "Speech recognition is turned off. Allow it in Settings to dictate prompts."
            return false
        @unknown default:
            errorMessage = "Speech recognition isn't available on this device."
            return false
        }

        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard microphoneGranted else {
            errorMessage = "Microphone access is turned off. Allow it in Settings to dictate prompts."
            return false
        }
        return true
    }

    // MARK: - Teardown

    private func reset() {
        isListening = false
        isPreparing = false
        isFinalizing = false

        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        request?.endAudio()

        audioEngine = nil
        request = nil
        task = nil
        recognizer = nil
        update = nil
        baseText = ""

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func message(for error: Error) -> String {
        if (error as NSError).domain == "kAFAssistantErrorDomain" {
            return "Dictation stopped. Tap the microphone to try again."
        }
        return error.localizedDescription
    }

    private enum DictationError: LocalizedError {
        case noMicrophone

        var errorDescription: String? {
            "No microphone input is available."
        }
    }
}

/// Microphone toggle used beside a prompt field. It fills `text` as the user
/// speaks and keeps the existing draft as a prefix.
struct VoiceInputButton: View {
    @ObservedObject var dictation: SpeechDictation
    @Binding var text: String
    var iconSize: CGFloat = 20

    var body: some View {
        Button {
            Task {
                await dictation.toggle(text: text) { updated in
                    text = updated
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if dictation.isPreparing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                            .font(.system(size: iconSize, weight: .medium))
                            .foregroundStyle(dictation.isListening ? Theme.danger : Color.secondary)
                    }
                }
                .frame(width: iconSize * 1.55, height: iconSize * 1.55)
                .background(
                    Circle()
                        .fill(dictation.isListening ? Theme.danger.opacity(0.12) : Color.clear)
                )

                if dictation.isListening {
                    PulsingDot(color: Theme.danger, size: 3.5)
                        .offset(x: 1, y: -1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(dictation.isPreparing)
        .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate prompt")
        .accessibilityHint("Speaks your prompt into the text field")
        .help(dictation.isListening ? "Stop dictation" : "Dictate prompt")
        .alert("Dictation unavailable", isPresented: errorPresented) {
            #if os(iOS)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                dictation.errorMessage = nil
            }
            #endif
            Button("OK", role: .cancel) {
                dictation.errorMessage = nil
            }
        } message: {
            Text(dictation.errorMessage ?? "")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { dictation.errorMessage != nil },
            set: { presented in
                if !presented { dictation.errorMessage = nil }
            }
        )
    }
}
