import SwiftTerm
import SwiftUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// What a SwiftTerm host needs from a remote session. Both OpenCode PTYs and
/// VM serial consoles implement it, so the emulator is shared.
@MainActor
protocol TerminalSession: AnyObject {
    func attach(_ view: SwiftTerm.TerminalView)
    func detach(_ view: SwiftTerm.TerminalView)
    func send(_ data: ArraySlice<UInt8>)
    func resize(cols: Int, rows: Int)
}

/// SwiftTerm host that feeds a remote terminal connection. The terminal view
/// owns rendering, selection and keyboard handling; this wrapper only bridges
/// its input, resize and clipboard events to the connection.
struct TerminalEmulatorView<Session: ObservableObject & TerminalSession>: View {
    @ObservedObject var connection: Session

    var body: some View {
        #if os(macOS)
        MacTerminalRepresentable(connection: connection)
        #else
        MobileTerminalRepresentable(connection: connection)
        #endif
    }
}

#if os(macOS)
private struct MacTerminalRepresentable<Session: ObservableObject & TerminalSession>: NSViewRepresentable {
    let connection: Session

    func makeCoordinator() -> TerminalCoordinator<Session> {
        TerminalCoordinator(connection: connection)
    }

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let view = SwiftTerm.TerminalView(frame: .zero)
        configure(view)
        view.terminalDelegate = context.coordinator
        connection.attach(view)
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) {
        context.coordinator.connection = connection
    }

    static func dismantleNSView(_ nsView: SwiftTerm.TerminalView, coordinator: TerminalCoordinator<Session>) {
        coordinator.connection.detach(nsView)
    }
}
#else
private struct MobileTerminalRepresentable<Session: ObservableObject & TerminalSession>: UIViewRepresentable {
    let connection: Session

    func makeCoordinator() -> TerminalCoordinator<Session> {
        TerminalCoordinator(connection: connection)
    }

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let view = SwiftTerm.TerminalView(frame: .zero)
        configure(view)
        view.terminalDelegate = context.coordinator
        connection.attach(view)
        DispatchQueue.main.async {
            _ = view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        context.coordinator.connection = connection
    }

    static func dismantleUIView(_ uiView: SwiftTerm.TerminalView, coordinator: TerminalCoordinator<Session>) {
        coordinator.connection.detach(uiView)
    }
}
#endif

private func configure(_ view: SwiftTerm.TerminalView) {
    #if os(macOS)
    view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    view.nativeBackgroundColor = NSColor(srgbRed: 0.052, green: 0.062, blue: 0.085, alpha: 1)
    view.nativeForegroundColor = NSColor(srgbRed: 0.87, green: 0.91, blue: 0.95, alpha: 1)
    #else
    view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    view.nativeBackgroundColor = UIColor(red: 0.052, green: 0.062, blue: 0.085, alpha: 1)
    view.nativeForegroundColor = UIColor(red: 0.87, green: 0.91, blue: 0.95, alpha: 1)
    #endif
}

/// Terminal delegate shared by both platforms. SwiftTerm can call these from
/// its own input paths, so every hand-off bounces back to the main actor.
private final class TerminalCoordinator<Session: ObservableObject & TerminalSession>: NSObject, TerminalViewDelegate {
    var connection: Session

    init(connection: Session) {
        self.connection = connection
    }

    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        Task { @MainActor [connection] in
            connection.resize(cols: newCols, rows: newRows)
        }
    }

    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

    func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        Task { @MainActor [connection] in
            connection.send(data)
        }
    }

    func scrolled(source: SwiftTerm.TerminalView, position: Double) {}

    func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    func bell(source: SwiftTerm.TerminalView) {
        #if os(macOS)
        NSSound.beep()
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    func clipboardRead(source: SwiftTerm.TerminalView) -> Data? {
        #if os(macOS)
        NSPasteboard.general.string(forType: .string)?.data(using: .utf8)
        #else
        UIPasteboard.general.string?.data(using: .utf8)
        #endif
    }

    func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}

    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
}
