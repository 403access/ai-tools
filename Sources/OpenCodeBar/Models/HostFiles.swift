import Foundation

/// A shortcut shown at the top of the host file browser. Mirrors the roots
/// returned by `GET /api/files`.
struct HostFileRoot: Decodable, Identifiable, Hashable, Sendable {
    var name: String
    var path: String
    var kind: String?

    var id: String { path }
    var icon: String {
        switch kind {
        case "home": return "house"
        case "root": return "internaldrive"
        case "applications": return "app.dashed"
        case "volumes", "mounts": return "externaldrive"
        case "logs": return "doc.text.magnifyingglass"
        case "temp": return "clock"
        default: return "folder"
        }
    }
}

/// One entry in a host directory listing.
struct HostFileEntry: Decodable, Identifiable, Hashable, Sendable {
    var name: String
    var path: String
    var kind: String
    var isDirectory: Bool
    var size: Int64?
    var modified: Double?
    var permissions: String?
    var hidden: Bool
    var linkTarget: String?
    var error: String?

    var id: String { path }

    var modifiedDate: Date? {
        modified.map { Date(timeIntervalSince1970: $0 / 1_000) }
    }

    var icon: String {
        if isDirectory { return "folder.fill" }
        switch kind {
        case "symlink": return "link"
        default: break
        }
        switch (name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "avif", "tiff", "bmp", "ico":
            return "photo"
        case "swift", "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "java", "kt", "c", "h", "cpp", "hpp", "cs", "php", "sh", "zsh", "bash":
            return "chevron.left.forwardslash.chevron.right"
        case "md", "markdown", "txt", "log":
            return "doc.text"
        case "json", "yaml", "yml", "toml", "plist", "xml", "entitlements":
            return "curlybraces"
        case "zip", "gz", "tar", "tgz", "bz2", "xz", "7z", "dmg", "pkg":
            return "archivebox"
        case "mp4", "mov", "m4v", "avi", "mkv", "webm":
            return "film"
        case "mp3", "wav", "flac", "aac", "m4a", "ogg":
            return "waveform"
        case "pdf":
            return "doc.richtext"
        default:
            return "doc"
        }
    }
}

/// One directory returned by `GET /api/files`.
struct HostDirectory: Decodable, Sendable {
    var path: String
    var name: String
    var parent: String?
    var roots: [HostFileRoot]
    var entries: [HostFileEntry]
    var total: Int
    var truncated: Bool
}

/// The text or image preview returned by `GET /api/files/content`.
struct HostFileContent: Decodable, Sendable {
    var path: String
    var name: String
    var size: Int64
    var modified: Double
    var kind: String
    var mime: String
    var content: String?
    var truncated: Bool
    var maxBytes: Int64

    var modifiedDate: Date {
        Date(timeIntervalSince1970: modified / 1_000)
    }

    var isImage: Bool { kind == "image" }
    var isText: Bool { kind == "text" }
}

struct HostDirectoryEnvelope: Decodable, Sendable {
    var data: HostDirectory
}

struct HostFileContentEnvelope: Decodable, Sendable {
    var data: HostFileContent
}
