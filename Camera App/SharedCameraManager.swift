import SwiftUI
import AVFoundation
import UIKit

struct BackgroundCameraView: UIViewControllerRepresentable {
    @Binding var isEnabled: Bool

    class Coordinator: NSObject {
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black

        // Setup session
        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            print("❌ Erreur accès caméra arrière")
            return viewController
        }

        session.addInput(input)

        // Frame rate + économie
        do {
            try device.lockForConfiguration()
            device.automaticallyAdjustsVideoHDREnabled = false
            if let range = device.activeFormat.videoSupportedFrameRateRanges.first {
                let fps = min(range.maxFrameRate, 15)
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(fps))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(fps))
            }
            device.unlockForConfiguration()
        } catch {
            print("⚠️ Erreur configuration device: \(error)")
        }

        // Setup preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = UIScreen.main.bounds

        // Insert into view hierarchy
        viewController.view.layer.addSublayer(previewLayer)

        // Blur effect
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(blurView)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor)
        ])

        // Overlay semi-transparent
        let overlay = UIView()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor)
        ])

        // Store in context
        context.coordinator.session = session
        context.coordinator.previewLayer = previewLayer

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let session = context.coordinator.session else { return }

        if isEnabled {
            if !session.isRunning {
                DispatchQueue.global(qos: .background).async {
                    session.startRunning()
                }
            }
        } else {
            if session.isRunning {
                DispatchQueue.global(qos: .background).async {
                    session.stopRunning()
                }
            }
        }

        // Update preview frame in case of rotation
        if let previewLayer = context.coordinator.previewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiViewController.view.bounds
            }
        }
    }
}
