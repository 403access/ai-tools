import AVFoundation
import FluidAudio
import Foundation

/// Local speech recognition with Parakeet on the Neural Engine.
///
/// The models download once (a few hundred megabytes) and then every utterance
/// is transcribed on the device. `SlidingWindowAsrManager` re-decodes
/// overlapping windows of audio, which gives live partial text without sending
/// anything off the machine.
@MainActor
final class ParakeetDictationEngine: DictationEngine {
    var onTranscript: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private var manager: SlidingWindowAsrManager?
    private var updates: Task<Void, Never>?
    private var capture: MicrophoneCapture?
    private var latest = ""

    func prepare(reportProgress: @escaping (Double, String) -> Void) async throws {
        let models = try await ParakeetModelStore.shared.load { progress in
            // The download stack calls this from a background queue.
            let fraction = progress.fractionCompleted
            let status = ParakeetModelStore.status(for: progress.phase)
            Task { @MainActor in reportProgress(fraction, status) }
        }

        let manager = SlidingWindowAsrManager(config: .streaming)
        try await manager.loadModels(models)
        self.manager = manager
    }

    func startCapture() async throws {
        guard let manager else {
            throw DictationFailure(message: "The speech model isn't loaded yet.")
        }

        // Subscribe before audio starts so no early window is dropped.
        let stream = await manager.transcriptionUpdates
        updates = Task { [weak self] in
            for await _ in stream {
                guard let self else { return }
                let confirmed = await manager.confirmedTranscript
                let volatile = await manager.volatileTranscript
                let text = Self.join(confirmed, volatile)
                self.latest = text
                self.onTranscript?(text)
            }
        }

        try await manager.startStreaming(source: .microphone)

        let capture = MicrophoneCapture()
        do {
            try capture.start { buffer in
                guard let copy = MicrophoneCapture.copy(buffer) else { return }
                Task { await manager.streamAudio(copy) }
            }
        } catch {
            updates?.cancel()
            updates = nil
            await manager.cancel()
            throw error
        }
        self.capture = capture
    }

    func finish() async -> String {
        capture?.stop()
        capture = nil

        var final = latest
        if let manager {
            if let text = try? await manager.finish(), !text.isEmpty {
                final = text
            }
        }

        updates?.cancel()
        updates = nil
        manager = nil
        latest = final
        await ParakeetModelStore.shared.scheduleRelease()
        return final
    }

    func cancel() async {
        capture?.stop()
        capture = nil
        updates?.cancel()
        updates = nil
        if let manager {
            await manager.cancel()
        }
        manager = nil
        latest = ""
        await ParakeetModelStore.shared.scheduleRelease()
    }

    /// Confirmed text followed by the still-changing tail.
    private static func join(_ confirmed: String, _ volatile: String) -> String {
        [confirmed, volatile]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Downloads and holds the Parakeet models.
///
/// Loading takes a few seconds and about 600 MB of memory, so the models stay
/// resident between utterances and are released after a quiet period rather
/// than being reloaded for every tap.
actor ParakeetModelStore {
    static let shared = ParakeetModelStore()

    private var models: AsrModels?
    private var inFlight: Task<AsrModels, Error>?
    private var releaseTask: Task<Void, Never>?

    /// English dictation gets the English-only model, which has the best
    /// recall. Other languages need the multilingual model.
    static var version: AsrModelVersion {
        let language = Locale.preferredLanguages.first ?? "en"
        return language.lowercased().hasPrefix("en") ? .v2 : .ultra
    }

    /// Application Support rather than Caches: re-downloading half a gigabyte
    /// because the system purged a cache directory would be a poor surprise.
    ///
    /// FluidAudio writes each model repository beside the URL it is handed, so
    /// the `parakeet-*` folders end up in `.../Models`. Creating the directory
    /// is left to FluidAudio; it owns the layout.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("OpenCodeBar", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Parakeet", isDirectory: true)
    }

    func load(
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> AsrModels {
        releaseTask?.cancel()
        releaseTask = nil

        if let models { return models }
        if let inFlight { return try await inFlight.value }

        let directory = Self.directory
        let version = Self.version
        let task = Task {
            try await AsrModels.downloadAndLoad(
                to: directory,
                version: version,
                progressHandler: progress
            )
        }
        inFlight = task

        do {
            let loaded = try await task.value
            models = loaded
            inFlight = nil
            return loaded
        } catch {
            inFlight = nil
            throw error
        }
    }

    /// Frees the loaded CoreML models after a quiet period.
    func scheduleRelease(after seconds: Double = 300) {
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.release()
        }
    }

    private func release() {
        models = nil
        releaseTask = nil
    }

    static func status(for phase: DownloadPhase) -> String {
        switch phase {
        case .listing:
            return "Finding the speech model…"
        case .downloading:
            return "Downloading the speech model…"
        case .compiling:
            return "Preparing the speech model…"
        }
    }
}
