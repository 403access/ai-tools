import Combine
import Foundation
import ImageIO
import UIKit

/// Drives one remote-desktop WebSocket. The hub sends JPEG frames as binary
/// messages and accepts small JSON input messages; everything else (capture,
/// permissions, display selection) stays on the Mac.
@MainActor
final class RemoteDesktopConnection: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)

        var label: String {
            switch self {
            case .idle: return "Not connected"
            case .connecting: return "Connecting…"
            case .connected: return "Connected"
            case .failed(let reason): return reason
            }
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        var isBusy: Bool {
            if case .connecting = self { return true }
            return false
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var status: RemoteDesktopStatus?
    @Published private(set) var image: CGImage?
    @Published private(set) var imageSize: CGSize = .zero
    @Published private(set) var framesPerSecond: Double = 0
    @Published private(set) var lastFrameAt: Date?
    @Published private(set) var logs: [String] = []
    @Published var modifiers: Set<RemoteModifier> = []

    private var api: HubAPI?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    private var decoding = false
    private var pendingFrame: Data?
    private var latestSequence: UInt32 = 0
    private var frameTimes: [Date] = []
    private var shouldReconnect = false
    /// Invalidates in-flight decodes when the socket is torn down or replaced.
    private var generation = 0

    // MARK: - Lifecycle

    func connect(api: HubAPI) {
        self.api = api
        shouldReconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil

        if socket != nil { return }
        state = .connecting
        logs.removeAll()
        latestSequence = 0
        frameTimes.removeAll()
        framesPerSecond = 0
        pendingFrame = nil
        decoding = false
        generation += 1

        do {
            let request = try api.remoteSocketRequest()
            let socket = URLSession.shared.webSocketTask(with: request)
            self.socket = socket
            socket.resume()
            receiveTask = Task { [weak self] in
                await self?.receiveLoop(socket)
            }
            startStatusPolling()
        } catch {
            state = .failed(message(for: error))
            scheduleReconnect()
        }
    }

    /// Leaves the Mac's capture running briefly; the hub stops it after the
    /// last viewer disconnects.
    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        statusTask?.cancel()
        statusTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        sendTask?.cancel()
        sendTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        pendingFrame = nil
        decoding = false
        latestSequence = 0
        generation += 1
        if state.isConnected || state.isBusy {
            state = .idle
        }
    }

    func refreshStatus() async {
        guard let api else { return }
        do {
            let next = try await api.remoteStatus()
            apply(status: next)
        } catch {
            if status == nil {
                state = .failed(message(for: error))
            }
        }
    }

    func requestPermissions(screenRecording: Bool, accessibility: Bool) async {
        guard let api else { return }
        do {
            let next = try await api.requestRemotePermissions(
                screenRecording: screenRecording,
                accessibility: accessibility
            )
            apply(status: next)
            // The prompt is on the Mac; re-check after the user has had time to
            // flip the switch in System Settings.
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if let updated = try? await api.remoteStatus() {
                    apply(status: updated)
                    let screenReady = !screenRecording || updated.screenRecording
                    let controlReady = !accessibility || updated.accessibility
                    if screenReady && controlReady { return }
                }
            }
        } catch {
            logs.append(message(for: error))
        }
    }

    func configure(fps: Int, quality: Double, maxWidth: Int) {
        let message: [String: Any] = [
            "type": "configure",
            "fps": fps,
            "quality": quality,
            "maxWidth": maxWidth,
        ]
        if socket != nil {
            send(message)
        } else if let api {
            Task { [weak self] in
                if let next = try? await api.configureRemote(
                    fps: fps,
                    quality: quality,
                    maxWidth: maxWidth
                ) {
                    self?.apply(status: next)
                }
            }
        }
    }

    func selectDisplay(_ id: UInt32) {
        if socket != nil {
            send(["type": "configure", "displayID": id])
        } else if let api {
            Task { [weak self] in
                if let next = try? await api.configureRemote(displayID: id) {
                    self?.apply(status: next)
                }
            }
        }
    }

    // MARK: - Input

    func pointer(
        _ action: String,
        x: Double,
        y: Double,
        button: String = "left",
        clickCount: Int = 1
    ) {
        send([
            "type": "pointer",
            "action": action,
            "x": x,
            "y": y,
            "button": button,
            "clickCount": clickCount,
        ])
    }

    func click(x: Double, y: Double, button: String = "left", clickCount: Int = 1) {
        pointer("down", x: x, y: y, button: button, clickCount: clickCount)
        pointer("up", x: x, y: y, button: button, clickCount: clickCount)
    }

    func scroll(dx: Double, dy: Double, x: Double, y: Double) {
        send([
            "type": "scroll",
            "dx": dx,
            "dy": dy,
            "x": x,
            "y": y,
        ])
    }

    func sendKey(_ name: String, modifiers extra: Set<RemoteModifier>? = nil) {
        let active = extra ?? modifiers
        var message: [String: Any] = [
            "type": "key",
            "key": name,
        ]
        if !active.isEmpty {
            message["modifiers"] = active.map(\.rawValue)
        }
        send(message)
        modifiers.removeAll()
    }

    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        var message: [String: Any] = ["type": "text", "text": text]
        if !modifiers.isEmpty {
            message["modifiers"] = modifiers.map(\.rawValue)
        }
        send(message)
        modifiers.removeAll()
    }

    func toggle(_ modifier: RemoteModifier) {
        if modifiers.contains(modifier) {
            modifiers.remove(modifier)
        } else {
            modifiers.insert(modifier)
        }
    }

    // MARK: - Socket

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    handle(json: text)
                case .data(let data):
                    handle(frame: data)
                @unknown default:
                    break
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            if self.socket === socket {
                self.socket = nil
                state = .failed(message(for: error))
                scheduleReconnect()
            }
        }
    }

    private func handle(json text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return }

        switch type {
        case "status":
            guard let payload = object["data"],
                  let statusData = try? JSONSerialization.data(withJSONObject: payload),
                  let decoded = try? HubAPI.decoder.decode(
                      RemoteDesktopStatus.self,
                      from: statusData
                  )
            else { return }
            apply(status: decoded)

        case "log":
            if let message = object["message"] as? String, !message.isEmpty {
                logs.append(message)
                if logs.count > 20 { logs.removeFirst(logs.count - 20) }
            }

        case "error":
            if let message = object["message"] as? String {
                state = .failed(message)
            }

        default:
            break
        }
    }

    private func handle(frame data: Data) {
        guard let parsed = RemoteDesktopFrame.parse(data) else { return }
        if parsed.header.sequence != 0, parsed.header.sequence <= latestSequence {
            return
        }
        latestSequence = parsed.header.sequence

        if decoding {
            // Keep only the newest frame while the decoder is busy.
            pendingFrame = data
            return
        }
        decode(parsed.jpeg, header: parsed.header)
    }

    private func decode(_ jpeg: Data, header: RemoteDesktopFrame.Header) {
        decoding = true
        let generation = generation
        Task.detached(priority: .userInitiated) { [weak self] in
            let source = CGImageSourceCreateWithData(jpeg as CFData, [
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
            let image = source.flatMap {
                CGImageSourceCreateImageAtIndex($0, 0, nil)
            }
            guard let self else { return }
            await self.applyDecoded(image, header: header, generation: generation)
        }
    }

    private func applyDecoded(
        _ image: CGImage?,
        header: RemoteDesktopFrame.Header,
        generation: Int
    ) {
        guard generation == self.generation else { return }
        decoding = false

        if let image {
            self.image = image
            imageSize = CGSize(width: header.width, height: header.height)
            lastFrameAt = Date()
            noteFrame()
            if !state.isConnected {
                state = .connected
            }
        }

        if let pending = pendingFrame {
            pendingFrame = nil
            if let parsed = RemoteDesktopFrame.parse(pending) {
                decode(parsed.jpeg, header: parsed.header)
            }
        }
    }

    private func noteFrame() {
        let now = Date()
        frameTimes.append(now)
        if frameTimes.count > 12 {
            frameTimes.removeFirst(frameTimes.count - 12)
        }
        guard let first = frameTimes.first, frameTimes.count > 1 else {
            framesPerSecond = 0
            return
        }
        let elapsed = now.timeIntervalSince(first)
        framesPerSecond = elapsed > 0
            ? Double(frameTimes.count - 1) / elapsed
            : 0
    }

    private func apply(status next: RemoteDesktopStatus) {
        status = next
        if !next.available {
            state = .failed(
                next.error
                    ?? "Remote desktop is not available. Run `make remote-host` on the Mac and restart the hub."
            )
            return
        }
        if !next.screenRecording {
            state = .failed("Screen Recording permission is required on the Mac.")
            return
        }
        if case .failed = state {
            state = .connecting
        }
        if next.streaming, !state.isConnected, !state.isBusy {
            state = .connecting
        }
    }

    private func startStatusPolling() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshStatus()
            }
        }
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self, let api = self.api else { return }
            self.connect(api: api)
        }
    }

    private func send(_ object: [String: Any]) {
        guard socket != nil,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return }

        let previous = sendTask
        sendTask = Task { [weak self] in
            _ = await previous?.value
            guard let self, let socket = self.socket else { return }
            try? await socket.send(.string(text))
        }
    }

    private func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? String(describing: apiError)
        }
        return error.localizedDescription
    }
}
