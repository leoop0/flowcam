// SharedCameraManager.swift
// Unifie le flux caméra pour le preview et le fond flouté

import AVFoundation
import UIKit

class SharedCameraManager: NSObject {
    static let shared = SharedCameraManager()

    private let session = AVCaptureSession()
    private var input: AVCaptureDeviceInput?

    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.shared.queue")

    var previewLayer: AVCaptureVideoPreviewLayer?
    private var pixelBufferHandler: ((CVPixelBuffer) -> Void)?

    private override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            print("[CameraManager] Erreur d'initialisation")
            return
        }

        session.addInput(input)
        self.input = input

        if session.canAddOutput(videoOutput) {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        self.previewLayer = preview

        session.commitConfiguration()
    }

    func start() {
        if !session.isRunning {
            queue.async {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        if session.isRunning {
            queue.async {
                self.session.stopRunning()
            }
        }
    }

    func setPixelBufferHandler(_ handler: @escaping (CVPixelBuffer) -> Void) {
        self.pixelBufferHandler = handler
    }

    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        return previewLayer
    }
}

extension SharedCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        pixelBufferHandler?(pixelBuffer)
    }
}
