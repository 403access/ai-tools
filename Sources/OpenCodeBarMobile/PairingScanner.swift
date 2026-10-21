import AVFoundation
import SwiftUI
import UIKit

/// Sheet for pairing with the Mac by scanning the QR code shown in its
/// Settings tab. The payload is the same `opencodebar://pair` link the Copy
/// button shares, so both paths end in `HubSettingsStore.applyPairingLink`.
struct PairingScannerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onPair: (String) -> Void

    @State private var permission: CameraPermission = .checking

    private enum CameraPermission: Equatable {
        case checking
        case authorized
        case denied
        case unavailable
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch permission {
                case .checking:
                    ProgressView()
                        .tint(.white)
                case .authorized:
                    PairingCameraView(
                        onCode: { code in
                            onPair(code)
                            dismiss()
                        },
                        onUnavailable: { permission = .unavailable }
                    )
                    .ignoresSafeArea()

                    VStack {
                        Spacer()
                        Text("Point the camera at the QR code in OpenCodeBar on your Mac.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.horizontal, 24)
                            .padding(.bottom, 28)
                    }
                case .denied:
                    CameraNotice(
                        icon: "camera.fill",
                        title: "Camera access is off",
                        message: "Allow camera access in Settings to scan a pairing code, or paste the link instead.",
                        actionTitle: "Open Settings"
                    ) {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                case .unavailable:
                    CameraNotice(
                        icon: "camera.metering.unknown",
                        title: "No camera available",
                        message: "This device cannot scan a code. Paste the pairing link instead."
                    )
                }
            }
            .navigationTitle("Scan pairing code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task { await resolvePermission() }
    }

    private func resolvePermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .authorized
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
            permission = granted ? .authorized : .denied
        default:
            permission = .denied
        }
    }
}

// MARK: - Camera

/// Wraps the capture session in a plain view controller. The preview fills the
/// sheet, and only `opencodebar://` payloads are reported so incidental QR
/// codes in view are ignored.
private struct PairingCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onUnavailable: () -> Void

    func makeUIViewController(context: Context) -> PairingCameraController {
        let controller = PairingCameraController()
        controller.onCode = onCode
        controller.onUnavailable = onUnavailable
        return controller
    }

    func updateUIViewController(_ controller: PairingCameraController, context: Context) {}
}

private final class PairingCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onUnavailable: (() -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "dev.opencodebar.pairing-scanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasReported = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            reportUnavailable()
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            reportUnavailable()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            reportUnavailable()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    private func reportUnavailable() {
        DispatchQueue.main.async { [weak self] in
            self?.onUnavailable?()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasReported,
              let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = code.stringValue,
              value.lowercased().hasPrefix("opencodebar://")
        else { return }

        hasReported = true
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
        onCode?(value)
    }
}

// MARK: - Notices

private struct CameraNotice: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(28)
    }
}
