#!/usr/bin/env swift
//
// Generates the OpenCodeBar app icon into an .iconset directory.
// Called by Scripts/build-app.sh; safe to run directly too.
//
//   swift Scripts/make-icon.swift Assets/AppIcon.iconset
//
import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(1)
}

let outputDir = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let gradientTop = NSColor(calibratedRed: 0.38, green: 0.93, blue: 0.68, alpha: 1).cgColor
let gradientBottom = NSColor(calibratedRed: 0.07, green: 0.50, blue: 0.42, alpha: 1).cgColor

func drawIcon(in context: CGContext, size: CGFloat) {
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let inset = size * 0.045
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = size * 0.225

    context.saveGState()
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(path)
    context.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [gradientTop, gradientBottom] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )
    context.restoreGState()

    // Terminal prompt glyph: "</>" rendered in monospace.
    let text = "</>" as NSString
    let font = NSFont.monospacedSystemFont(ofSize: size * 0.44, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedWhite: 0.05, alpha: 0.88),
    ]
    let textSize = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2 + size * 0.02),
        withAttributes: attributes
    )
}

func png(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    rep.size = NSSize(width: pixels, height: pixels)

    guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    drawIcon(in: graphics.cgContext, size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let data = png(pixels: variant.pixels) else {
        FileHandle.standardError.write(Data("failed to render \(variant.name)\n".utf8))
        exit(1)
    }
    let url = outputDir.appendingPathComponent("\(variant.name).png")
    try data.write(to: url)
}

print("Wrote icon set to \(outputDir.path)")
