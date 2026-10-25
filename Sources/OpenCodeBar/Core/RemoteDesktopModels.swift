import Foundation

/// One display on the Mac running the hub.
struct RemoteDisplayInfo: Codable, Identifiable, Equatable, Hashable {
    let id: UInt32
    let name: String
    let width: Int
    let height: Int
    let scale: Double
    let primary: Bool

    var aspectRatio: Double {
        width > 0 && height > 0 ? Double(width) / Double(height) : 16.0 / 9.0
    }
}

/// Snapshot of the hub's screen-capture helper. `available` is false when the
/// helper binary has not been built; `screenRecording` and `accessibility` are
/// the two macOS privacy permissions the helper needs.
struct RemoteDesktopStatus: Codable, Equatable {
    var available: Bool
    var running: Bool
    var viewers: Int
    var version: String?
    var screenRecording: Bool
    var accessibility: Bool
    var displays: [RemoteDisplayInfo]
    var displayID: UInt32?
    var fps: Int
    var quality: Double
    var maxWidth: Int
    var streaming: Bool
    var error: String?

    static let unavailable = RemoteDesktopStatus(
        available: false,
        running: false,
        viewers: 0,
        version: nil,
        screenRecording: false,
        accessibility: false,
        displays: [],
        displayID: nil,
        fps: 12,
        quality: 0.6,
        maxWidth: 1600,
        streaming: false,
        error: nil
    )

    var display: RemoteDisplayInfo? {
        if let displayID, let match = displays.first(where: { $0.id == displayID }) {
            return match
        }
        return displays.first(where: \.primary) ?? displays.first
    }
}

struct RemoteStatusEnvelope: Codable {
    let data: RemoteDesktopStatus
}

/// Header shared by the hub and both clients. A binary WebSocket message is:
///
///     [kind: 0x02]["R"]["D"][sequence: UInt32][timestamp: UInt32]
///     [width: UInt16][height: UInt16][JPEG bytes]
///
/// The sequence lets a slow decoder drop an older frame instead of painting it
/// over a newer one.
enum RemoteDesktopFrame {
    static let kind: UInt8 = 2
    static let headerLength = 15

    struct Header {
        let sequence: UInt32
        let timestamp: UInt32
        let width: Int
        let height: Int
    }

    static func parse(_ data: Data) -> (header: Header, jpeg: Data)? {
        guard data.count > headerLength else { return nil }
        let bytes = [UInt8](data.prefix(headerLength))
        guard bytes[0] == kind, bytes[1] == 0x52, bytes[2] == 0x44 else { return nil }

        func uint32(_ offset: Int) -> UInt32 {
            (UInt32(bytes[offset]) << 24)
                | (UInt32(bytes[offset + 1]) << 16)
                | (UInt32(bytes[offset + 2]) << 8)
                | UInt32(bytes[offset + 3])
        }
        func uint16(_ offset: Int) -> Int {
            (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
        }

        let header = Header(
            sequence: uint32(3),
            timestamp: uint32(7),
            width: uint16(11),
            height: uint16(13)
        )
        return (header, data.dropFirst(headerLength))
    }
}

/// A modifier the phone can hold for the next key. Values match the names the
/// host helper understands.
enum RemoteModifier: String, CaseIterable, Identifiable, Hashable {
    case command = "cmd"
    case control = "ctrl"
    case option = "opt"
    case shift = "shift"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        }
    }

    var title: String {
        switch self {
        case .command: return "Command"
        case .control: return "Control"
        case .option: return "Option"
        case .shift: return "Shift"
        }
    }
}
