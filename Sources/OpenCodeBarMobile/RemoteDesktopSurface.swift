import SwiftUI
import UIKit

/// Zoomable, letterboxed view of the Mac's display. One finger drives the
/// pointer, pinch zooms the canvas, a two-finger tap toggles zoom, and a
/// two-finger pan scrolls the Mac when the canvas is not zoomed.
struct RemoteDesktopSurface: UIViewRepresentable {
    let image: CGImage?
    let imageSize: CGSize
    var isEnabled: Bool
    var zoomToken: Int
    var onPointer: (_ action: String, _ x: Double, _ y: Double, _ button: String, _ clicks: Int) -> Void
    var onScroll: (_ dx: Double, _ dy: Double, _ x: Double, _ y: Double) -> Void

    func makeUIView(context: Context) -> RemoteCanvasView {
        let view = RemoteCanvasView()
        view.isEnabled = isEnabled
        view.onPointer = onPointer
        view.onScroll = onScroll
        return view
    }

    func updateUIView(_ view: RemoteCanvasView, context: Context) {
        view.isEnabled = isEnabled
        view.onPointer = onPointer
        view.onScroll = onScroll
        view.setImage(image, size: imageSize)
        if view.zoomToken != zoomToken {
            view.zoomToken = zoomToken
            view.toggleZoom()
        }
    }
}

final class RemoteCanvasView: UIView, UIGestureRecognizerDelegate {
    var onPointer: ((String, Double, Double, String, Int) -> Void)?
    var onScroll: ((Double, Double, Double, Double) -> Void)?
    var isEnabled = true {
        didSet { isUserInteractionEnabled = isEnabled }
    }
    var zoomToken = 0

    private let contentLayer = CALayer()
    private var imageSize: CGSize = .zero
    private var baseSize: CGSize = .zero
    private var canvasScale: CGFloat = 1
    private var canvasOffset: CGPoint = .zero
    private var pinchStartScale: CGFloat = 1
    private var lastScrollTranslation: CGPoint = .zero
    private var dragged = false
    private var initialZoomApplied = false

    private var singleTap: UITapGestureRecognizer!
    private var doubleTap: UITapGestureRecognizer!
    private var twoFingerTap: UITapGestureRecognizer!
    private var singlePan: UIPanGestureRecognizer!
    private var twoFingerPan: UIPanGestureRecognizer!
    private var pinch: UIPinchGestureRecognizer!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        layer.masksToBounds = true

        contentLayer.contentsGravity = .resize
        contentLayer.masksToBounds = true
        contentLayer.backgroundColor = UIColor.black.cgColor
        contentLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(contentLayer)

        singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)

        twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2

        singlePan = UIPanGestureRecognizer(target: self, action: #selector(handleSinglePan))
        singlePan.maximumNumberOfTouches = 1

        twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.delegate = self

        pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        pinch.delegate = self

        for gesture in [singleTap!, doubleTap!, twoFingerTap!, singlePan!, twoFingerPan!, pinch!] {
            addGestureRecognizer(gesture)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: CGImage?, size: CGSize) {
        contentLayer.contents = image
        let changed = size != imageSize
        imageSize = size
        if changed {
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        baseSize = Self.aspectFit(imageSize, in: bounds)
        if !initialZoomApplied,
           imageSize.width > 0,
           bounds.width > 200,
           bounds.height > 200,
           baseSize.height > 0 {
            initialZoomApplied = true
            // A landscape Mac display leaves a lot of empty space in portrait.
            // Start with a modest crop so text is readable; the Zoom button and
            // a two-finger tap return to the full-screen fit.
            let fill = min(2.4, max(1, bounds.height * 0.82 / baseSize.height))
            if fill > 1.15 {
                canvasScale = fill
                canvasOffset = .zero
            }
        }
        clampOffset()
        contentLayer.bounds = CGRect(origin: .zero, size: baseSize)
        contentLayer.position = CGPoint(
            x: bounds.midX + canvasOffset.x,
            y: bounds.midY + canvasOffset.y
        )
        contentLayer.transform = CATransform3DMakeScale(canvasScale, canvasScale, 1)
    }

    private static func aspectFit(_ size: CGSize, in bounds: CGRect) -> CGSize {
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: bounds.width, height: bounds.height)
        }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func normalized(_ point: CGPoint) -> (x: Double, y: Double)? {
        guard contentLayer.bounds.width > 0, contentLayer.bounds.height > 0 else {
            return nil
        }
        let local = contentLayer.convert(point, from: layer)
        let x = min(max(local.x / contentLayer.bounds.width, 0), 1)
        let y = min(max(local.y / contentLayer.bounds.height, 0), 1)
        return (Double(x), Double(y))
    }

    private func pointer(_ action: String, at point: CGPoint, clicks: Int = 1) {
        guard let value = normalized(point) else { return }
        onPointer?(action, value.x, value.y, "left", clicks)
    }

    // MARK: - Taps

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        pointer("down", at: point)
        pointer("up", at: point)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        // A real double click is two down/up pairs with clickState 1 then 2;
        // one event with clickState 2 is ignored by some AppKit controls.
        pointer("down", at: point, clicks: 1)
        pointer("up", at: point, clicks: 1)
        pointer("down", at: point, clicks: 2)
        pointer("up", at: point, clicks: 2)
    }

    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if canvasScale > 1.02 {
            resetZoom()
        } else {
            zoom(to: 2.4, around: point)
        }
    }

    // MARK: - Drag

    @objc private func handleSinglePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            dragged = false
            pointer("down", at: point)
        case .changed:
            dragged = true
            pointer("drag", at: point)
        case .ended, .cancelled, .failed:
            if dragged {
                pointer("up", at: point)
            }
            dragged = false
        default:
            break
        }
    }

    @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        let translation = gesture.translation(in: self)

        switch gesture.state {
        case .began:
            lastScrollTranslation = .zero
        case .changed:
            let delta = CGPoint(
                x: translation.x - lastScrollTranslation.x,
                y: translation.y - lastScrollTranslation.y
            )
            lastScrollTranslation = translation

            if canvasScale > 1.02 {
                canvasOffset.x += delta.x
                canvasOffset.y += delta.y
                clampOffset()
                setNeedsLayout()
            } else if let value = normalized(point) {
                // Wheel deltas are in pixels; a finger swipe should move a
                // sensible amount of content, not one pixel per point.
                onScroll?(
                    Double(-delta.x * 2.0),
                    Double(-delta.y * 2.0),
                    value.x,
                    value.y
                )
            }
        case .ended, .cancelled, .failed:
            lastScrollTranslation = .zero
        default:
            break
        }
    }

    // MARK: - Zoom

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartScale = canvasScale
        case .changed:
            canvasScale = min(max(pinchStartScale * gesture.scale, 1), 4)
            clampOffset()
            setNeedsLayout()
        case .ended, .cancelled, .failed:
            if canvasScale < 1.04 {
                resetZoom()
            } else {
                clampOffset()
                setNeedsLayout()
            }
        default:
            break
        }
    }

    private func zoom(to scale: CGFloat, around point: CGPoint) {
        canvasScale = scale
        canvasOffset = CGPoint(
            x: (bounds.midX - point.x) * (scale - 1),
            y: (bounds.midY - point.y) * (scale - 1)
        )
        clampOffset()
        setNeedsLayout()
    }

    func toggleZoom() {
        if canvasScale > 1.02 {
            resetZoom()
        } else {
            zoom(to: 2.3, around: CGPoint(x: bounds.midX, y: bounds.midY))
        }
    }

    private func resetZoom() {
        canvasScale = 1
        canvasOffset = .zero
        setNeedsLayout()
    }

    private func clampOffset() {
        let scaledWidth = baseSize.width * canvasScale
        let scaledHeight = baseSize.height * canvasScale
        let maxX = max((scaledWidth - bounds.width) / 2, 0)
        let maxY = max((scaledHeight - bounds.height) / 2, 0)
        canvasOffset.x = min(max(canvasOffset.x, -maxX), maxX)
        canvasOffset.y = min(max(canvasOffset.y, -maxY), maxY)
    }

    // MARK: - Gesture delegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // Pinch and the two-finger pan both need two fingers, and pinch should
        // not cancel a pan while the user is zooming.
        let pair = [gestureRecognizer, other]
        return pair.contains(pinch) && pair.contains(twoFingerPan)
    }
}
