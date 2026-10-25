import AppKit
import Foundation

NSApplication.shared.setActivationPolicy(.prohibited)

let host = RemoteHost()
host.start()
WireInput.start { line in
    host.handle(line: line)
}
NSApplication.shared.run()
