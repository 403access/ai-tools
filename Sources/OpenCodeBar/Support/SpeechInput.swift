import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Live speech-to-text for the prompt composers.
///
/// Runs the local Parakeet model on the Neural Engine and falls back to the
/// system recognizer when the model cannot be prepared. Whatever the engine,
/// the transcript is appended to the draft the user already typed and stays
/// editable.
@MainActor
final class SpeechDictation: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isPreparing = false
    /// 0...1 while the local model downloads or compiles, otherwise nil.
    @Published private(set) var preparationProgress: Double?
    @Published private(set) var preparationStatus: String?
    @Published var errorMessage: String?

    private var engine: (any DictationEngine)?
    private var baseText = ""
    private var update: ((String) -> Void)?
    private var isFinalizing = false
    /// Guards against a late `finish()` from a previous session writing into a
    /// new draft after the user tapped the microphone again.
    private var sessionID = 0

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

        // Drop a previous session that is still finalizing so its results
        // cannot feed into this one.
        discardEngine()
        sessionID &+= 1
        let session = sessionID

        errorMessage = nil
        isPreparing = true
        baseText = text
        self.update = update
        preparationProgress = nil
        preparationStatus = nil
        defer { isPreparing = false }

        let engine = ParakeetDictationEngine()
        engine.onTranscript = { [weak self] spoken in self?.receive(spoken) }
        engine.onFailure = { [weak self] message in self?.fail(message) }
        self.engine = engine

        do {
            try await engine.prepare { [weak self] fraction, status in
                guard let self, self.sessionID == session else { return }
                self.preparationProgress = fraction
                self.preparationStatus = status
            }
        } catch {
            guard sessionID == session else { return }
            // The local model needs a one-time download. When that fails, keep
            // dictation working with the system recognizer instead of leaving
            // the button dead.
            DevLog.shared.record(
                "Local speech model unavailable",
                category: .app,
                level: .warning,
                detail: "Falling back to system dictation: \(error.localizedDescription)"
            )
            let fallback = AppleDictationEngine()
            fallback.onTranscript = { [weak self] spoken in self?.receive(spoken) }
            fallback.onFailure = { [weak self] message in self?.fail(message) }
            self.engine = fallback
            do {
                try await fallback.prepare { _, _ in }
            } catch {
                guard sessionID == session else { return }
                self.engine = nil
                self.update = nil
                self.baseText = ""
                errorMessage = error.localizedDescription
                return
            }
        }

        // The view may have disappeared while the permission sheet or the model
        // download was in progress.
        guard sessionID == session, isPreparing, self.update != nil, let engine = self.engine else {
            return
        }

        do {
            try await engine.startCapture()
        } catch {
            guard sessionID == session else { return }
            self.engine = nil
            self.update = nil
            self.baseText = ""
            errorMessage = error.localizedDescription
            return
        }

        guard sessionID == session else { return }
        isListening = true
        preparationProgress = nil
        preparationStatus = nil
    }

    /// Stops listening and lets the engine finalize the last words.
    func stop() {
        guard isListening || isPreparing, !isFinalizing else { return }

        isListening = false
        isPreparing = false
        isFinalizing = true
        preparationProgress = nil
        preparationStatus = nil

        let session = sessionID
        let engine = self.engine
        Task {
            let final = await engine?.finish() ?? ""
            self.finishSession(session, transcript: final)
        }
        // Watchdog: an engine that stalls must never leave the button stuck in
        // the finalizing state.
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self.finishSession(session, transcript: "")
        }
    }

    /// Stops immediately, discarding any late recognition callbacks.
    func cancel() {
        guard engine != nil || isListening || isPreparing else { return }

        sessionID &+= 1
        discardEngine()
        isListening = false
        isPreparing = false
        isFinalizing = false
        preparationProgress = nil
        preparationStatus = nil
    }

    // MARK: - Session

    private func receive(_ spoken: String) {
        guard let update else { return }
        update(joined(baseText, spoken))
    }

    private func finishSession(_ session: Int, transcript: String) {
        guard session == sessionID else { return }
        if !transcript.isEmpty {
            receive(transcript)
        }
        discardEngine()
        isFinalizing = false
    }

    private func fail(_ message: String) {
        errorMessage = message
        discardEngine()
        isListening = false
        isPreparing = false
        isFinalizing = false
    }

    private func discardEngine() {
        guard let engine else {
            update = nil
            baseText = ""
            return
        }
        self.engine = nil
        update = nil
        baseText = ""
        Task { await engine.cancel() }
    }

    private func joined(_ base: String, _ spoken: String) -> String {
        guard !spoken.isEmpty else { return base }
        guard !base.isEmpty else { return spoken }
        if base.hasSuffix(" ") || base.hasSuffix("\n") { return base + spoken }
        return base + " " + spoken
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
                        DictationProgressRing(
                            progress: dictation.preparationProgress,
                            size: iconSize
                        )
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
        .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate prompt")
        .accessibilityHint("Speaks your prompt into the text field")
        .help(helpText)
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

    private var helpText: String {
        if dictation.isPreparing {
            return dictation.preparationStatus ?? "Preparing dictation"
        }
        return dictation.isListening ? "Stop dictation" : "Dictate prompt"
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

/// Spinner with a determinate arc while the speech model downloads.
private struct DictationProgressRing: View {
    var progress: Double?
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 2)

            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.02, min(progress, 1)))
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.2), value: progress)
    }
}
