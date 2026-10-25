import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import ScreenCaptureKit

private struct HostDisplay {
    let id: CGDirectDisplayID
    let name: String
    let width: Int
    let height: Int
    let scale: Double
    let primary: Bool

    var json: [String: Any] {
        [
            "id": Int(id),
            "name": name,
            "width": width,
            "height": height,
            "scale": scale,
            "primary": primary,
        ]
    }
}

/// The host half of remote desktop. ScreenCaptureKit produces frames, Core
/// Graphics posts input, and both directions use the wire format in Wire.swift.
final class RemoteHost: NSObject, SCStreamOutput, SCStreamDelegate {
    private let version = "1.0.0"

    private var displayID: CGDirectDisplayID
    private var fps: Int
    private var quality: Double
    private var maxWidth: Int

    private var displays: [HostDisplay] = []
    private var stream: SCStream?
    private var starting = false
    private var streaming = false
    private var encoding = false
    private var errorMessage: String?
    private var retryTask: Task<Void, Never>?
    private var lastStatusAt: TimeInterval = 0
    private var lastInputNoticeAt: TimeInterval = 0

    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let samples = DispatchQueue(
        label: "dev.opencodebar.remote.samples",
        qos: .userInteractive
    )

    override init() {
        let main = CGMainDisplayID()
        displayID = main
        fps = 12
        quality = 0.6
        maxWidth = 1600
        super.init()

        var requestedDisplay: CGDirectDisplayID?
        var index = 1
        let arguments = CommandLine.arguments
        while index < arguments.count {
            let argument = arguments[index]
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil
            switch argument {
            case "--fps":
                if let next, let value = Int(next) { fps = min(max(value, 1), 30) }
                index += 2
            case "--quality":
                if let next, let value = Double(next) { quality = min(max(value, 0.1), 1) }
                index += 2
            case "--max-width":
                if let next, let value = Int(next) { maxWidth = min(max(value, 480), 3840) }
                index += 2
            case "--display":
                if let next, let value = UInt32(next) { requestedDisplay = value }
                index += 2
            default:
                index += 1
            }
        }
        if let requestedDisplay { displayID = requestedDisplay }
    }

    func start() {
        refreshDisplays()
        emitStatus()
        log("Remote host \(version) ready · display \(displayID)")
    }

    // MARK: - Commands

    func handle(line: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else {
            log("Ignored an unreadable command", level: "warn")
            return
        }

        switch type {
        case "start":
            startCapture()

        case "stop":
            stopCapture()

        case "configure":
            configure(object)

        case "pointer":
            pointer(object)

        case "scroll":
            scroll(object)

        case "key":
            key(object)

        case "text":
            if let text = object["text"] as? String {
                typeText(text, modifiers: strings(object["modifiers"]))
            }

        case "status":
            emitStatus(force: true)

        case "permissions":
            requestPermissions(object)

        default:
            log("Unknown command: \(type)", level: "warn")
        }
    }

    private func configure(_ object: [String: Any]) {
        if let value = int(object["fps"]) { fps = min(max(value, 1), 30) }
        if let value = double(object["quality"]) { quality = min(max(value, 0.1), 1) }
        if let value = int(object["maxWidth"]) {
            maxWidth = min(max(value, 480), 3840)
        }
        if let value = int(object["displayID"]), value > 0 {
            let next = CGDirectDisplayID(value)
            if next != displayID {
                displayID = next
                refreshDisplays()
            }
        }

        if streaming {
            stopCapture(restart: true)
        } else {
            emitStatus(force: true)
        }
    }

    // MARK: - Capture

    private func startCapture() {
        guard !streaming, !starting else { return }
        guard isScreenRecordingAllowed() else {
            // The first call asks macOS to add the helper to Screen Recording.
            // The user may still need to flip the switch in System Settings.
            _ = CGRequestScreenCaptureAccess()
            errorMessage = "Screen Recording permission is required for OpenCodeBar Remote Host."
            emitStatus(force: true)
            schedulePermissionRetry()
            return
        }

        starting = true
        errorMessage = nil
        emitStatus(force: true)

        Task.detached { [weak self] in
            await self?.beginStream()
        }
    }

    private func beginStream() async {
        do {
            log("requesting shareable content")
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            log("shareable content: \(content.displays.count) displays")
            let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first
            guard let display else {
                throw HostError.noDisplay
            }
            if display.displayID != displayID {
                displayID = display.displayID
                refreshDisplays()
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let target = targetSize(for: display)
            let configuration = SCStreamConfiguration()
            configuration.width = target.width
            configuration.height = target.height
            configuration.minimumFrameInterval = CMTime(
                value: 1,
                timescale: CMTimeScale(max(fps, 1))
            )
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = true
            configuration.queueDepth = 2
            configuration.capturesAudio = false
            configuration.colorSpaceName = CGColorSpace.sRGB

            let stream = SCStream(
                filter: filter,
                configuration: configuration,
                delegate: self
            )
            try stream.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: samples
            )
            log("starting capture \(target.width)x\(target.height)")
            try await stream.startCapture()

            self.stream = stream
            starting = false
            streaming = true
            retryTask?.cancel()
            retryTask = nil
            errorMessage = nil
            emitStatus(force: true)
            log("Capturing \(target.width)×\(target.height) at \(fps) fps")
        } catch {
            starting = false
            streaming = false
            stream = nil
            errorMessage = error.localizedDescription
            emitStatus(force: true)
            log("Capture failed: \(error.localizedDescription)", level: "error")
            if !isScreenRecordingAllowed() {
                schedulePermissionRetry()
            }
        }
    }

    private func stopCapture(restart: Bool = false) {
        retryTask?.cancel()
        retryTask = nil

        guard let stream else {
            streaming = false
            starting = false
            emitStatus(force: true)
            if restart { startCapture() }
            return
        }

        self.stream = nil
        streaming = false
        stream.stopCapture { [weak self] error in
            guard let self else { return }
            if let error {
                self.log("Stopping capture failed: \(error.localizedDescription)", level: "warn")
            }
            self.emitStatus(force: true)
            if restart {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.startCapture()
                }
            }
        }
    }

    private func targetSize(for display: SCDisplay) -> (width: Int, height: Int) {
        // SCDisplay reports logical points on a scaled Retina display; capture
        // at the mode's real pixel size and let maxWidth do the downsizing.
        let mode = CGDisplayCopyDisplayMode(display.displayID)
        let modeWidth = mode?.pixelWidth ?? 0
        let modeHeight = mode?.pixelHeight ?? 0
        let sourceWidth = max(
            modeWidth > 0 ? modeWidth : CGDisplayPixelsWide(display.displayID),
            1
        )
        let sourceHeight = max(
            modeHeight > 0 ? modeHeight : CGDisplayPixelsHigh(display.displayID),
            1
        )
        guard sourceWidth > maxWidth else {
            return (even(sourceWidth), even(sourceHeight))
        }
        let scale = Double(maxWidth) / Double(sourceWidth)
        return (even(maxWidth), even(Int((Double(sourceHeight) * scale).rounded())))
    }

    private func even(_ value: Int) -> Int {
        max(value - (value % 2), 2)
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
            let frame = attachments.first,
            let statusValue = frame[.status] as? Int,
            statusValue == SCFrameStatus.complete.rawValue
        else { return }

        guard !encoding else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        encoding = true
        defer { encoding = false }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(
                rawValue: kCGImageDestinationLossyCompressionQuality as String
            ): quality
        ]
        guard let jpeg = ciContext.jpegRepresentation(
            of: image,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: options
        ) else { return }

        WireOutput.shared.frame(jpeg: jpeg, width: width, height: height)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stream = nil
            self.streaming = false
            self.starting = false
            self.errorMessage = error.localizedDescription
            self.emitStatus(force: true)
            self.log("Capture stopped: \(error.localizedDescription)", level: "error")
        }
    }

    // MARK: - Permission

    private func isScreenRecordingAllowed() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func requestPermissions(_ object: [String: Any]) {
        if bool(object["screenRecording"]) == true {
            if !isScreenRecordingAllowed() {
                _ = CGRequestScreenCaptureAccess()
            }
            if streaming == false { startCapture() }
        }
        if bool(object["accessibility"]) == true {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        emitStatus(force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.emitStatus(force: true)
        }
    }

    private func schedulePermissionRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled, !self.streaming else { return }
                if self.isScreenRecordingAllowed() {
                    self.startCapture()
                    return
                }
                self.emitStatus(force: true)
            }
        }
    }

    // MARK: - Input

    private func pointer(_ object: [String: Any]) {
        guard inputAllowed() else { return }
        let action = (object["action"] as? String) ?? "move"
        guard let x = double(object["x"]), let y = double(object["y"]) else { return }
        let point = globalPoint(x: x, y: y)
        let button = (object["button"] as? String) ?? "left"
        let clickCount = max(int(object["clickCount"]) ?? 1, 1)
        let source = CGEventSource(stateID: .hidSystemState)

        switch action {
        case "move":
            postMouse(.mouseMoved, at: point, button: button, clickCount: 1, source: source)
        case "down":
            postMouse(.leftMouseDown, at: point, button: button, clickCount: clickCount, source: source)
        case "up":
            postMouse(.leftMouseUp, at: point, button: button, clickCount: clickCount, source: source)
        case "drag":
            postMouse(.leftMouseDragged, at: point, button: button, clickCount: 1, source: source)
        default:
            break
        }
    }

    private func postMouse(
        _ type: CGEventType,
        at point: CGPoint,
        button: String,
        clickCount: Int,
        source: CGEventSource?
    ) {
        let isRight = button == "right"
        let isOther = button == "middle" || button == "other"
        let eventType: CGEventType
        let mouseButton: CGMouseButton

        switch type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            if isRight {
                eventType = type == .leftMouseDown ? .rightMouseDown
                    : type == .leftMouseUp ? .rightMouseUp
                    : .rightMouseDragged
                mouseButton = .right
            } else if isOther {
                eventType = type == .leftMouseDown ? .otherMouseDown
                    : type == .leftMouseUp ? .otherMouseUp
                    : .otherMouseDragged
                mouseButton = .center
            } else {
                eventType = type
                mouseButton = .left
            }
        default:
            eventType = type
            mouseButton = .left
        }

        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: eventType,
            mouseCursorPosition: point,
            mouseButton: mouseButton
        ) else { return }
        if eventType == .leftMouseDown || eventType == .rightMouseDown
            || eventType == .otherMouseDown
        {
            event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        }
        event.post(tap: .cghidEventTap)
    }

    private func scroll(_ object: [String: Any]) {
        guard inputAllowed() else { return }
        let dx = int32(object["dx"]) ?? 0
        let dy = int32(object["dy"]) ?? 0
        guard dx != 0 || dy != 0 else { return }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: dy,
            wheel2: dx,
            wheel3: 0
        ) else { return }
        if let x = double(object["x"]), let y = double(object["y"]) {
            event.location = globalPoint(x: x, y: y)
        }
        event.post(tap: .cghidEventTap)
    }

    private func key(_ object: [String: Any]) {
        guard inputAllowed() else { return }
        let name = ((object["key"] as? String) ?? "").lowercased()
        let code = int(object["keyCode"]).flatMap { UInt16(exactly: $0) }
            ?? Self.keyCodes[name]
            ?? 0
        let flags = flags(strings(object["modifiers"]))
        let action = object["action"] as? String
        let source = CGEventSource(stateID: .hidSystemState)

        if action != "up", let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: code,
            keyDown: true
        ) {
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        if action != "down", let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: code,
            keyDown: false
        ) {
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    private func typeText(_ text: String, modifiers: [String]) {
        guard inputAllowed(), !text.isEmpty else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = flags(modifiers)

        // `keyboardSetUnicodeString` is capped at 20 UTF-16 units per event and
        // must not split a surrogate pair. Chunk on Character boundaries.
        var chunk = ""
        for character in text {
            chunk.append(character)
            if chunk.utf16.count >= 16 {
                postText(chunk, flags: flags, source: source)
                chunk = ""
            }
        }
        if !chunk.isEmpty {
            postText(chunk, flags: flags, source: source)
        }
    }

    private func postText(_ text: String, flags: CGEventFlags, source: CGEventSource?) {
        let units = Array(text.utf16)
        guard !units.isEmpty,
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        else { return }
        units.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            down.flags = flags
            down.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: base
            )
            down.post(tap: .cghidEventTap)
        }

        if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            units.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                up.flags = flags
                up.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: base
                )
                up.post(tap: .cghidEventTap)
            }
        }
    }

    private func flags(_ modifiers: [String]) -> CGEventFlags {
        var result: CGEventFlags = []
        for modifier in modifiers.map({ $0.lowercased() }) {
            switch modifier {
            case "cmd", "command": result.insert(.maskCommand)
            case "ctrl", "control": result.insert(.maskControl)
            case "opt", "option", "alt": result.insert(.maskAlternate)
            case "shift": result.insert(.maskShift)
            case "fn", "function": result.insert(.maskSecondaryFn)
            default: break
            }
        }
        return result
    }

    private func inputAllowed() -> Bool {
        guard AXIsProcessTrusted() else {
            let now = Date().timeIntervalSince1970
            if now - lastInputNoticeAt > 5 {
                lastInputNoticeAt = now
                log("Accessibility permission is required to control the Mac", level: "warn")
                emitStatus(force: true)
            }
            return false
        }
        return true
    }

    private func globalPoint(x: Double, y: Double) -> CGPoint {
        let bounds = CGDisplayBounds(displayID)
        return CGPoint(
            x: bounds.minX + min(max(x, 0), 1) * bounds.width,
            y: bounds.minY + min(max(y, 0), 1) * bounds.height
        )
    }

    // MARK: - Status

    private func refreshDisplays() {
        if !Thread.isMainThread {
            DispatchQueue.main.sync { self.refreshDisplays() }
            return
        }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            displays = []
            return
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            displays = []
            return
        }

        var names: [CGDirectDisplayID: String] = [:]
        var scales: [CGDirectDisplayID: Double] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { continue }
            let id = CGDirectDisplayID(number.uint32Value)
            names[id] = screen.localizedName
            scales[id] = Double(screen.backingScaleFactor)
        }

        displays = ids.map { id in
            let bounds = CGDisplayBounds(id)
            return HostDisplay(
                id: id,
                name: names[id] ?? "Display \(id)",
                width: Int(bounds.width),
                height: Int(bounds.height),
                scale: scales[id] ?? 1,
                primary: CGDisplayIsMain(id) != 0
            )
        }

        if !displays.contains(where: { $0.id == displayID }) {
            displayID = CGMainDisplayID()
        }
    }

    private func emitStatus(force: Bool = false) {
        let now = Date().timeIntervalSince1970
        if !force, now - lastStatusAt < 0.2 { return }
        lastStatusAt = now

        var payload: [String: Any] = [
            "type": "status",
            "version": version,
            "screenRecording": isScreenRecordingAllowed(),
            "accessibility": AXIsProcessTrusted(),
            "displays": displays.map(\.json),
            "displayID": Int(displayID),
            "fps": fps,
            "quality": quality,
            "maxWidth": maxWidth,
            "streaming": streaming,
        ]
        if let errorMessage {
            payload["error"] = errorMessage
        }
        WireOutput.shared.status(payload)
    }

    private func log(_ message: String, level: String = "info") {
        WireOutput.shared.log(message, level: level)
    }

    // MARK: - JSON helpers

    private func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private func int32(_ value: Any?) -> Int32? {
        guard let number = value as? NSNumber else { return nil }
        return number.int32Value
    }

    private func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private func bool(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

    private func strings(_ value: Any?) -> [String] {
        (value as? [String]) ?? []
    }

    private static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36,
        "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
        "`": 50, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "right": 124, "arrowright": 124, "left": 123, "arrowleft": 123,
        "down": 125, "arrowdown": 125, "up": 126, "arrowup": 126,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "forwarddelete": 117, "f1": 122, "f2": 120, "f3": 99, "f4": 118,
        "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
        "f11": 103, "f12": 111,
    ]
}

private enum HostError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No display is available to capture."
        }
    }
}
