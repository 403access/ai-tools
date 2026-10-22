#!/usr/bin/env swift
//
// Generates the OpenCodeBar app icon into an .iconset directory.
// Called by Scripts/build-app.sh; safe to run directly too.
//
//   swift Scripts/make-icon.swift Assets/AppIcon.iconset
//   swift Scripts/make-icon.swift --full-bleed .build/ios-icon.iconset
//
// The mark mirrors the menu bar's SF Symbol "terminal": a dark squircle with a
// terminal window, an accent-green prompt chevron and a glowing cursor block.
// --full-bleed fills the canvas edge to edge (for iOS, which applies its own
// rounded mask) instead of drawing a transparent macOS-style squircle.
//
import AppKit

let arguments = CommandLine.arguments
let fullBleed = arguments.contains("--full-bleed")
guard let outputPath = arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift [--full-bleed] <output.iconset>\n".utf8))
    exit(1)
}

let outputDir = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// Dark-theme palette, kept in sync with Theme.swift.
let accent = (r: CGFloat(0.30), g: CGFloat(0.85), b: CGFloat(0.62))
let warn = (r: CGFloat(0.98), g: CGFloat(0.72), b: CGFloat(0.28))
let danger = (r: CGFloat(0.97), g: CGFloat(0.40), b: CGFloat(0.42))

func color(_ c: (r: CGFloat, g: CGFloat, b: CGFloat), _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
}

/// Apple-style squircle. A superellipse reads softer than a plain rounded rect
/// at icon sizes, especially in the Dock.
func squircle(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 240
    let a = rect.width / 2
    let b = rect.height / 2
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let ct = cos(t)
        let st = sin(t)
        let x = rect.midX + a * copysign(pow(abs(ct), 2 / exponent), ct)
        let y = rect.midY + b * copysign(pow(abs(st), 2 / exponent), st)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

func linearGradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations)!
}

func drawBackground(in context: CGContext, size: CGFloat) {
    let rect = fullBleed
        ? CGRect(x: 0, y: 0, width: size, height: size)
        : CGRect(x: size * 0.045, y: size * 0.045, width: size * 0.91, height: size * 0.91)

    context.saveGState()
    let shape = fullBleed ? CGPath(rect: rect, transform: nil) : squircle(in: rect)
    context.addPath(shape)
    context.clip()

    // Deep, cool charcoal with a hint of green in the highlight.
    let base = linearGradient(
        [color((0.135, 0.175, 0.170)), color((0.045, 0.062, 0.062)), color((0.022, 0.032, 0.034))],
        [0, 0.55, 1]
    )
    context.drawLinearGradient(
        base,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    // Accent bloom behind the window, like a screen glowing in the dark.
    let bloom = linearGradient(
        [color(accent, 0.30), color(accent, 0.10), color(accent, 0)],
        [0, 0.5, 1]
    )
    context.drawRadialGradient(
        bloom,
        startCenter: CGPoint(x: rect.midX, y: rect.midY - size * 0.04),
        startRadius: 0,
        endCenter: CGPoint(x: rect.midX, y: rect.midY - size * 0.04),
        endRadius: size * 0.52,
        options: [.drawsAfterEndLocation]
    )

    // Faint sheen across the top edge.
    let sheen = linearGradient([color((1, 1, 1), 0.075), color((1, 1, 1), 0)], [0, 1])
    context.drawLinearGradient(
        sheen,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.minX, y: rect.maxY - size * 0.28),
        options: []
    )

    context.restoreGState()

    // Hairline rim: bright at the top, dim at the bottom.
    if !fullBleed {
        context.saveGState()
        context.addPath(squircle(in: rect.insetBy(dx: size * 0.0015, dy: size * 0.0015)))
        context.setLineWidth(size * 0.003)
        context.setStrokeColor(color((1, 1, 1), 0.16))
        context.strokePath()
        context.restoreGState()
    }
}

/// The prompt glyph: a chevron followed by a cursor block.
func drawPrompt(
    in context: CGContext,
    center: CGPoint,
    width: CGFloat,
    height: CGFloat,
    lineWidth: CGFloat,
    cursorWidth: CGFloat,
    glow: Bool
) {
    let gap = width * 0.22
    let total = width + gap + cursorWidth
    let startX = center.x - total / 2
    let topY = center.y + height / 2
    let bottomY = center.y - height / 2

    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(lineWidth)
    context.setStrokeColor(color(accent))

    if glow {
        context.setShadow(offset: .zero, blur: lineWidth * 1.6, color: color(accent, 0.85))
    }

    let chevron = CGMutablePath()
    chevron.move(to: CGPoint(x: startX, y: topY))
    chevron.addLine(to: CGPoint(x: startX + width, y: center.y))
    chevron.addLine(to: CGPoint(x: startX, y: bottomY))
    context.addPath(chevron)
    context.strokePath()

    // Cursor sits on the baseline of the chevron.
    let cursorHeight = max(lineWidth, lineWidth * 1.05)
    let cursor = CGRect(
        x: startX + width + gap,
        y: bottomY + lineWidth * 0.10,
        width: cursorWidth,
        height: cursorHeight
    )
    context.addPath(CGPath(roundedRect: cursor, cornerWidth: lineWidth / 2, cornerHeight: lineWidth / 2, transform: nil))
    context.setFillColor(color(accent))
    context.fillPath()
    context.restoreGState()
}

func drawTerminal(in context: CGContext, size: CGFloat) {
    let full = size >= 128
    let micro = size < 48

    if micro {
        drawPrompt(
            in: context,
            center: CGPoint(x: size / 2, y: size / 2),
            width: size * 0.160,
            height: size * 0.180,
            lineWidth: max(size * 0.055, 1.5),
            cursorWidth: size * 0.140,
            glow: false
        )
        return
    }

    let width = size * (full ? 0.66 : 0.63)
    let height = size * (full ? 0.52 : 0.50)
    let window = CGRect(
        x: (size - width) / 2,
        y: (size - height) / 2 - size * 0.005,
        width: width,
        height: height
    )
    let windowPath = CGPath(
        roundedRect: window,
        cornerWidth: size * (full ? 0.075 : 0.060),
        cornerHeight: size * (full ? 0.075 : 0.060),
        transform: nil
    )

    // Drop shadow lifts the window off the backdrop.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.055,
        color: color((0, 0, 0), 0.62)
    )
    context.addPath(windowPath)
    context.setFillColor(color((0.035, 0.048, 0.050)))
    context.fillPath()
    context.restoreGState()

    // Screen.
    context.saveGState()
    context.addPath(windowPath)
    context.clip()

    let screen = linearGradient(
        [color((0.090, 0.120, 0.120)), color((0.022, 0.032, 0.034))],
        [0, 1]
    )
    context.drawLinearGradient(
        screen,
        start: CGPoint(x: window.midX, y: window.maxY),
        end: CGPoint(x: window.midX, y: window.minY),
        options: []
    )

    // Inner accent haze near the prompt.
    let haze = linearGradient([color(accent, 0.13), color(accent, 0)], [0, 1])
    context.drawRadialGradient(
        haze,
        startCenter: CGPoint(x: window.midX, y: window.minY + height * 0.28),
        startRadius: 0,
        endCenter: CGPoint(x: window.midX, y: window.minY + height * 0.28),
        endRadius: width * 0.48,
        options: [.drawsAfterEndLocation]
    )

    let titleBarHeight = full ? size * 0.105 : 0
    if full {
        let bar = CGRect(x: window.minX, y: window.maxY - titleBarHeight, width: width, height: titleBarHeight)
        context.setFillColor(color((1, 1, 1), 0.055))
        context.fill(bar)
        context.setStrokeColor(color((1, 1, 1), 0.07))
        context.setLineWidth(max(size * 0.0025, 1))
        context.move(to: CGPoint(x: window.minX, y: bar.minY))
        context.addLine(to: CGPoint(x: window.maxX, y: bar.minY))
        context.strokePath()

        // Traffic-light dots in the status colours.
        let dotRadius = size * 0.0145
        let dotGap = size * 0.045
        let dotY = bar.midY
        for (index, dot) in [danger, warn, accent].enumerated() {
            let center = CGPoint(x: window.minX + size * 0.055 + CGFloat(index) * dotGap, y: dotY)
            context.setFillColor(color(dot, 0.92))
            context.fillEllipse(in: CGRect(
                x: center.x - dotRadius,
                y: center.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
        }
    }

    context.restoreGState()

    // Window rim.
    context.saveGState()
    context.addPath(windowPath)
    context.setLineWidth(max(size * 0.004, 1))
    context.setStrokeColor(color(accent, full ? 0.32 : 0.38))
    context.strokePath()
    context.restoreGState()

    // Prompt, vertically centred in the screen area below the title bar.
    let bodyMinY = window.minY
    let bodyMaxY = full ? window.maxY - titleBarHeight : window.maxY
    let bodyCenter = CGPoint(x: window.midX, y: (bodyMinY + bodyMaxY) / 2)
    drawPrompt(
        in: context,
        center: bodyCenter,
        width: size * (full ? 0.108 : 0.100),
        height: size * (full ? 0.118 : 0.108),
        lineWidth: max(size * (full ? 0.029 : 0.032), 1.4),
        cursorWidth: size * (full ? 0.096 : 0.090),
        glow: full
    )
}

func drawIcon(in context: CGContext, size: CGFloat) {
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    drawBackground(in: context, size: size)
    drawTerminal(in: context, size: size)
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
