import AVFoundation
import UIKit

final class SharedCameraManager: NSObject {
    static let shared = SharedCameraManager()

    let session = AVCaptureSession()

    private var input: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.shared.queue")
    private var pixelBufferHandler: ((CVPixelBuffer) -> Void)?

    private(set) var currentDevice: AVCaptureDevice?
    var previewLayer: AVCaptureVideoPreviewLayer?

    private override init() {
        super.init()
        setupSession()
    }

    func getSession() -> AVCaptureSession? {
        session
    }

    func start() {
        guard !session.isRunning else { return }

        queue.async {
            self.session.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }

        queue.async {
            self.session.stopRunning()
        }
    }

    func setPixelBufferHandler(_ handler: @escaping (CVPixelBuffer) -> Void) {
        pixelBufferHandler = handler
    }

    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        previewLayer
    }

    func switchCamera() {
        session.beginConfiguration()

        NotificationCenter.default.removeObserver(
            self,
            name: .AVCaptureDeviceSubjectAreaDidChange,
            object: currentDevice
        )

        for input in session.inputs {
            session.removeInput(input)
        }

        guard let currentDevice else {
            session.commitConfiguration()
            return
        }

        let newPosition: AVCaptureDevice.Position = currentDevice.position == .back ? .front : .back
        let previousType = input?.device.deviceType
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            previousType ?? .builtInWideAngleCamera,
            .builtInWideAngleCamera,
            .builtInTrueDepthCamera
        ]

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: newPosition
        )

        guard
            let newDevice = discovery.devices.first,
            let newInput = try? AVCaptureDeviceInput(device: newDevice),
            session.canAddInput(newInput)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(newInput)
        input = newInput
        self.currentDevice = newDevice
        configureDevice(newDevice)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subjectAreaDidChange),
            name: .AVCaptureDeviceSubjectAreaDidChange,
            object: newDevice
        )

        if let connection = previewLayer?.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = newPosition == .front
        }

        session.commitConfiguration()
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        self.input = input
        currentDevice = device
        configureDevice(device)

        if session.canAddOutput(videoOutput) {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            session.addOutput(videoOutput)
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.cornerRadius = 46
        preview.masksToBounds = true
        previewLayer = preview

        session.commitConfiguration()
        setupSubjectAreaChangeNotification()
    }

    private func configureDevice(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }

            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            device.isSubjectAreaChangeMonitoringEnabled = true

            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .none
            }

            device.unlockForConfiguration()
        } catch {
            print("Failed to configure device: \(error)")
        }
    }

    private func setupSubjectAreaChangeNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subjectAreaDidChange),
            name: .AVCaptureDeviceSubjectAreaDidChange,
            object: currentDevice
        )
    }

    @objc private func subjectAreaDidChange(notification: NSNotification) {
        guard let device = currentDevice else { return }

        queue.async {
            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }

                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }

                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                device.unlockForConfiguration()
            } catch {
                print("Failed to refresh autofocus: \(error)")
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension SharedCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard CFGetTypeID(pixelBuffer) == CVPixelBufferGetTypeID() else { return }

        DispatchQueue.main.async { [weak self] in
            self?.pixelBufferHandler?(pixelBuffer)
        }
    }
}
