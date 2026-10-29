import AVFoundation
import Foundation

/// One speech-to-text backend behind `SpeechDictation`.
///
/// Engines publish the transcript for the current utterance as it grows, so the
/// coordinator can append it to whatever draft text was already in the field.
@MainActor
protocol DictationEngine: AnyObject {
    /// Receives the full transcript for the current utterance so far.
    var onTranscript: ((String) -> Void)? { get set }
    /// Receives a user-facing message when the engine stops unexpectedly.
    var onFailure: ((String) -> Void)? { get set }

    /// Asks for permissions and makes sure the model is ready. The progress
    /// callback reports model preparation in 0...1 with a short status line.
    func prepare(reportProgress: @escaping (Double, String) -> Void) async throws
    /// Starts microphone capture and begins streaming results to `onTranscript`.
    func startCapture() async throws
    /// Stops capture, flushes the last words, and returns the final transcript.
    func finish() async -> String
    /// Stops immediately and discards the transcript.
    func cancel() async
}

/// An engine failure that already carries a sentence fit for the alert.
struct DictationFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

/// Microphone capture shared by every engine.
///
/// Owns the audio engine and, on iOS, the audio session. The buffer handed to
/// `onBuffer` is only valid for the duration of the call; use `copy(_:)` when
/// the audio has to outlive it.
@MainActor
final class MicrophoneCapture {
    enum CaptureError: LocalizedError {
        case noMicrophone

        var errorDescription: String? { "No microphone input is available." }
    }

    private var engine: AVAudioEngine?

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let engine = AVAudioEngine()

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.noMicrophone
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            onBuffer(buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    func stop() {
        guard let engine else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Deep copy of a tap buffer so it stays valid after the callback returns.
    nonisolated static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard
            let copy = AVAudioPCMBuffer(
                pcmFormat: buffer.format,
                frameCapacity: buffer.frameLength
            )
        else { return nil }

        copy.frameLength = buffer.frameLength
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)

        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                memcpy(destination[channel], source[channel], frames * MemoryLayout<Float>.size)
            }
        } else if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0..<channels {
                memcpy(destination[channel], source[channel], frames * MemoryLayout<Int16>.size)
            }
        } else {
            return nil
        }
        return copy
    }
}
