import SwiftUI
import AVFoundation
import CoreImage
import ImageIO
import Photos

struct LensInfo {
    let deviceType: AVCaptureDevice.DeviceType
    let displayName: String
    let zoomFactor: String
    let isDigitalZoom: Bool

    static func availableLenses(position: AVCaptureDevice.Position) -> [LensInfo] {
        var lenses: [LensInfo] = []

        if position == .back {
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
                .builtInTelephotoCamera
            ]

            for deviceType in deviceTypes {
                if AVCaptureDevice.default(deviceType, for: .video, position: position) != nil {
                    switch deviceType {
                    case .builtInUltraWideCamera:
                        lenses.append(LensInfo(deviceType: deviceType, displayName: "Ultra Wide", zoomFactor: ".5x", isDigitalZoom: false))
                    case .builtInWideAngleCamera:
                        lenses.append(LensInfo(deviceType: deviceType, displayName: "Wide", zoomFactor: "1x", isDigitalZoom: false))
                        let hasTelephoto = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: position) != nil
                        if !hasTelephoto {
                            lenses.append(LensInfo(deviceType: deviceType, displayName: "Wide 2x", zoomFactor: "2x", isDigitalZoom: true))
                        }
                    case .builtInTelephotoCamera:
                        lenses.append(LensInfo(deviceType: deviceType, displayName: "Telephoto", zoomFactor: "3x", isDigitalZoom: false))
                    default:
                        break
                    }
                }
            }
        } else {
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInWideAngleCamera,
                .builtInTrueDepthCamera
            ]

            for deviceType in deviceTypes {
                if AVCaptureDevice.default(deviceType, for: .video, position: position) != nil {
                    switch deviceType {
                    case .builtInWideAngleCamera:
                        lenses.append(LensInfo(deviceType: deviceType, displayName: "Wide", zoomFactor: "1x", isDigitalZoom: false))
                    case .builtInTrueDepthCamera:
                        lenses.append(LensInfo(deviceType: deviceType, displayName: "TrueDepth", zoomFactor: "1x", isDigitalZoom: false))
                    default:
                        break
                    }
                }
            }
        }

        return lenses.enumerated().map { index, lens in
            let zoom = lens.zoomFactor.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = "\(index + 1)x"
            return zoom.isEmpty
                ? LensInfo(deviceType: lens.deviceType, displayName: lens.displayName, zoomFactor: fallback, isDigitalZoom: lens.isDigitalZoom)
                : lens
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    @Binding var frontCamera: Bool
    @Binding var takePhoto: Bool
    @Binding var switchCamera: Bool
    @Binding var switchLens: Bool
    @Binding var switchToLensIndex: Int?
    @Binding var availableLenses: [LensInfo]
    @Binding var currentLensIndex: Int
    @Binding var isUsingFrontCamera: Bool

    class Coordinator: NSObject, AVCapturePhotoCaptureDelegate {
        var parent: CameraView
        private var frontCamera: Binding<Bool>
        private let context = CIContext()
        private var output: AVCapturePhotoOutput?
        private var session: AVCaptureSession?
        private var currentInput: AVCaptureDeviceInput?
        private var isSwitching = false
        private var cachedLenses: [LensInfo] = []
        private var localLensIndex = 0

        init(frontCamera: Binding<Bool>, parent: CameraView) {
            self.parent = parent
            self.frontCamera = frontCamera
            self.output = AVCapturePhotoOutput()
            self.output?.isHighResolutionCaptureEnabled = true

            let sharedSession = SharedCameraManager.shared.session
            self.session = sharedSession

            if let output, sharedSession.canAddOutput(output) {
                sharedSession.addOutput(output)
            }
        }

        func updateAvailableLenses() {
            let position: AVCaptureDevice.Position = parent.isUsingFrontCamera ? .front : .back
            let validatedLenses = LensInfo.availableLenses(position: position).map { lens in
                if lens.zoomFactor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return LensInfo(deviceType: lens.deviceType, displayName: lens.displayName, zoomFactor: "?", isDigitalZoom: lens.isDigitalZoom)
                }
                return lens
            }

            cachedLenses = validatedLenses

            let wideIndex = validatedLenses.firstIndex { $0.zoomFactor == "1x" && !$0.isDigitalZoom } ?? 0

            DispatchQueue.main.async {
                self.parent.availableLenses = validatedLenses
                self.parent.currentLensIndex = wideIndex
                self.localLensIndex = wideIndex
            }
        }

        func switchToLens(at index: Int) {
            guard !isSwitching else { return }
            guard let session else { return }

            let lenses = cachedLenses
            guard index < lenses.count else { return }
            guard index != localLensIndex else { return }

            isSwitching = true

            let currentIndex = localLensIndex
            let targetLens = lenses[index]
            localLensIndex = index

            let position: AVCaptureDevice.Position = parent.isUsingFrontCamera ? .front : .back

            session.stopRunning()
            session.beginConfiguration()

            for input in session.inputs {
                session.removeInput(input)
            }

            guard let newDevice = AVCaptureDevice.default(targetLens.deviceType, for: .video, position: position),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                session.commitConfiguration()
                session.startRunning()
                localLensIndex = currentIndex
                isSwitching = false
                return
            }

            if session.canAddInput(newInput) {
                session.addInput(newInput)
                currentInput = newInput

                do {
                    try newDevice.lockForConfiguration()
                    configureFastExposure(for: newDevice)
                    newDevice.automaticallyAdjustsVideoHDREnabled = false

                    if targetLens.isDigitalZoom && targetLens.zoomFactor == "2x" {
                        newDevice.videoZoomFactor = 2.0
                    }

                    newDevice.unlockForConfiguration()
                } catch {
                    print("Erreur configuration lens : \(error)")
                }

                session.commitConfiguration()
                session.startRunning()

                DispatchQueue.main.async {
                    self.parent.currentLensIndex = index
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isSwitching = false
                }
            } else {
                session.commitConfiguration()
                session.startRunning()
                localLensIndex = currentIndex
                isSwitching = false
            }
        }

        func switchLens() {
            guard !isSwitching else { return }
            guard let session else { return }

            let lenses = cachedLenses
            guard !lenses.isEmpty else { return }

            isSwitching = true

            let currentIndex = localLensIndex
            let nextIndex = (currentIndex + 1) % lenses.count
            let nextLens = lenses[nextIndex]
            localLensIndex = nextIndex

            let position: AVCaptureDevice.Position = parent.isUsingFrontCamera ? .front : .back

            session.beginConfiguration()

            if let currentInput {
                session.removeInput(currentInput)
            }

            guard let newDevice = AVCaptureDevice.default(nextLens.deviceType, for: .video, position: position),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                session.commitConfiguration()
                localLensIndex = currentIndex
                isSwitching = false
                return
            }

            if session.canAddInput(newInput) {
                session.addInput(newInput)
                currentInput = newInput

                do {
                    try newDevice.lockForConfiguration()
                    configureFastExposure(for: newDevice)
                    newDevice.automaticallyAdjustsVideoHDREnabled = false
                    newDevice.unlockForConfiguration()
                } catch {
                    print("Erreur configuration lens : \(error)")
                }

                session.commitConfiguration()

                DispatchQueue.main.async {
                    self.parent.currentLensIndex = nextIndex
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.parent.switchLens = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.isSwitching = false
                    }
                }
            } else {
                session.commitConfiguration()
                localLensIndex = currentIndex
                DispatchQueue.main.async {
                    self.parent.switchLens = false
                }
                isSwitching = false
            }
        }

        func switchCamera() {
            guard !isSwitching else { return }
            guard let session else { return }

            isSwitching = true

            let currentPosition = currentInput?.device.position ?? .back
            let currentlyUsingFront = currentPosition == .front

            session.beginConfiguration()

            if let currentInput {
                session.removeInput(currentInput)
            }

            let newPosition: AVCaptureDevice.Position = currentlyUsingFront ? .back : .front

            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                session.commitConfiguration()
                isSwitching = false
                return
            }

            if session.canAddInput(newInput) {
                session.addInput(newInput)
                currentInput = newInput

                do {
                    try newDevice.lockForConfiguration()
                    configureFastExposure(for: newDevice)
                    newDevice.automaticallyAdjustsVideoHDREnabled = false
                    newDevice.unlockForConfiguration()
                } catch {
                    print("Erreur configuration appareil : \(error)")
                }

                let newState = newPosition == .front
                DispatchQueue.main.async {
                    self.parent.isUsingFrontCamera = newState
                    self.frontCamera.wrappedValue = newState
                    self.updateAvailableLenses()
                    self.parent.switchCamera = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isSwitching = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.parent.switchCamera = false
                }
                isSwitching = false
            }

            session.commitConfiguration()
        }

        func capturePhoto() {
            guard let output else { return }

            if let connection = output.connection(with: .video) {
                connection.videoOrientation = .portrait
                connection.isVideoMirrored = parent.isUsingFrontCamera
            }

            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true

            if #available(iOS 13.0, *) {
                settings.photoQualityPrioritization = .speed
            } else {
                settings.isAutoStillImageStabilizationEnabled = false
            }

            output.capturePhoto(with: settings, delegate: self)
        }

        func photoOutput(_ output: AVCapturePhotoOutput,
                         didFinishProcessingPhoto photo: AVCapturePhoto,
                         error: Error?) {
            guard error == nil else { return }
            guard let cgImage = photo.cgImageRepresentation() else { return }

            let orientationValue = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32 ?? 1
            let exifOrientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up

            var ciImage = CIImage(cgImage: cgImage).oriented(exifOrientation)

            if parent.isUsingFrontCamera {
                ciImage = ciImage
                    .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
                    .transformed(by: CGAffineTransform(translationX: ciImage.extent.width, y: 0))
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let processedImage = self.applyImageStyle(to: ciImage)
                DispatchQueue.main.async {
                    if let finalCGImage = self.context.createCGImage(processedImage, from: processedImage.extent) {
                        let uiImage = UIImage(cgImage: finalCGImage)
                        self.saveCompressedImage(uiImage, metadata: photo.metadata)
                    }
                }
            }
        }

        private func applyImageStyle(to image: CIImage) -> CIImage {
            let medium = (saturation: 1.08, contrast: 1.07, brightness: 0.01, grain: 0.02)

            var result = image
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: medium.saturation,
                    kCIInputContrastKey: medium.contrast,
                    kCIInputBrightnessKey: medium.brightness
                ])
                .applyingFilter("CIExposureAdjust", parameters: [
                    kCIInputEVKey: -0.3
                ])

            if let noise = CIFilter(name: "CIRandomGenerator")?.outputImage?
                .cropped(to: result.extent)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0, y: 0, z: 0, w: medium.grain),
                    "inputGVector": CIVector(x: 0, y: 0, z: 0, w: medium.grain),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0, w: medium.grain),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                ]) {
                result = CIFilter(name: "CIAdditionCompositing", parameters: [
                    kCIInputImageKey: noise,
                    kCIInputBackgroundImageKey: result
                ])?.outputImage ?? result
            }

            return result
        }

        private func configureFastExposure(for device: AVCaptureDevice) {
            do {
                try device.lockForConfiguration()
                let minDuration = CMTimeMake(value: 1, timescale: 250)
                let maxISO = min(device.activeFormat.maxISO, 1600)
                device.setExposureModeCustom(duration: minDuration, iso: maxISO, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                print("Erreur configuration expo rapide : \(error.localizedDescription)")
            }
        }

        private func saveCompressedImage(_ image: UIImage, metadata: [String: Any]?) {
            guard let compressedData = image.jpegData(compressionQuality: 0.4),
                  let source = CGImageSourceCreateWithData(compressedData as CFData, nil),
                  let type = CGImageSourceGetType(source) else { return }

            let destinationData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(destinationData as CFMutableData, type, 1, nil) else { return }

            var finalMetadata = metadata ?? [:]
            finalMetadata[kCGImagePropertyOrientation as String] = 1
            finalMetadata.removeValue(forKey: kCGImageSourceCreateThumbnailWithTransform as String)
            finalMetadata.removeValue(forKey: kCGImageSourceThumbnailMaxPixelSize as String)
            CGImageDestinationAddImageFromSource(destination, source, 0, finalMetadata as CFDictionary)
            CGImageDestinationFinalize(destination)

            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("compressed_photo.jpg")
            do {
                try destinationData.write(to: fileURL)

                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                }, completionHandler: { _, error in
                    if let error {
                        print("Erreur ajout galerie: \(error.localizedDescription)")
                    }
                })
            } catch {
                print("Erreur lors de la sauvegarde: \(error)")
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(frontCamera: $frontCamera, parent: self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        class CameraViewController: UIViewController {
            var previewLayer: AVCaptureVideoPreviewLayer?

            override func viewDidLayoutSubviews() {
                super.viewDidLayoutSubviews()
                guard let previewLayer else { return }

                previewLayer.frame = view.bounds
                previewLayer.cornerRadius = 46
                previewLayer.masksToBounds = true
            }
        }

        let controller = CameraViewController()
        controller.view.backgroundColor = .black

        guard let previewLayer = SharedCameraManager.shared.getPreviewLayer() else {
            return controller
        }

        controller.previewLayer = previewLayer
        controller.view.layer.addSublayer(previewLayer)

        context.coordinator.updateAvailableLenses()

        if !SharedCameraManager.shared.session.isRunning {
            SharedCameraManager.shared.start()
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if takePhoto {
            context.coordinator.capturePhoto()
            DispatchQueue.main.async {
                self.takePhoto = false
            }
        }

        if switchCamera {
            context.coordinator.switchCamera()
        }

        if switchLens {
            context.coordinator.switchLens()
        }

        if let previewLayer = SharedCameraManager.shared.getPreviewLayer() {
            DispatchQueue.main.async {
                previewLayer.frame = uiViewController.view.bounds
                previewLayer.cornerRadius = 46
                previewLayer.masksToBounds = true
            }
        }

        if let targetIndex = switchToLensIndex {
            DispatchQueue.main.async {
                self.switchCamera = false
            }
            context.coordinator.switchToLens(at: targetIndex)
            DispatchQueue.main.async {
                self.switchToLensIndex = nil
            }
        }
    }
}
