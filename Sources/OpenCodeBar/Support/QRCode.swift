import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders pairing links as QR codes for the Settings tab.
///
/// The generated image is one pixel per module; callers scale it with
/// nearest-neighbour interpolation so the modules stay crisp at any size.
enum QRCode {
    private static let context = CIContext()

    static func image(for string: String) -> NSImage? {
        guard let data = string.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        // Medium recovery keeps the code compact while tolerating fingerprints
        // and screen reflections.
        filter.correctionLevel = "M"

        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent)
        else { return nil }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: output.extent.width, height: output.extent.height)
        )
    }
}
