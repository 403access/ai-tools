import Foundation

// Entry point. A custom `main.swift` is used instead of `@main` so the app can
// run in a standalone preview mode that renders the panel in a normal window
// for screenshots and design iteration.
if CommandLine.arguments.contains("--preview") {
    MainActor.assumeIsolated { PreviewRunner.run() }
} else {
    OpenCodeBarApp.main()
}
