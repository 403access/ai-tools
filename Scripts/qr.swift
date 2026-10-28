import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Renders text (usually a URL) as a PNG QR code.
///
/// Used by `Scripts/deploy-ota.sh` so the install link can be scanned from the
/// Mac screen without copying it to the phone by hand. CoreImage is part of
/// macOS, so this needs no extra tooling.
///
/// Usage: swift Scripts/qr.swift <text> [output.png]

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: qr.swift <text> [output.png]\n".utf8))
    exit(2)
}

let text = arguments[1]
let output = arguments.count >= 3
    ? arguments[2]
    : FileManager.default.temporaryDirectory
        .appendingPathComponent("opencodebar-qr.png").path

let filter = CIFilter.qrCodeGenerator()
filter.message = Data(text.utf8)
// Medium correction keeps the code readable from a laptop screen at arm's
// length without making the modules too dense.
filter.correctionLevel = "M"

guard let image = filter.outputImage else {
    FileHandle.standardError.write(Data("qr: could not generate a code\n".utf8))
    exit(1)
}

// CIQRCodeGenerator emits one pixel per module. Scale it up without
// interpolation so the result stays crisp at any size.
let scale: CGFloat = 12
let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
let context = CIContext()
guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
    FileHandle.standardError.write(Data("qr: could not render the code\n".utf8))
    exit(1)
}

let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("qr: could not encode the image\n".utf8))
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: output))
} catch {
    FileHandle.standardError.write(Data("qr: \(error.localizedDescription)\n".utf8))
    exit(1)
}

print(output)
