// SharedCameraManager.swift - Version autofocus automatique uniquement
import AVFoundation
import UIKit

class SharedCameraManager: NSObject {
    static let shared = SharedCameraManager()
    
    let session = AVCaptureSession()
    private var input: AVCaptureDeviceInput?
    
    public private(set) var currentDevice: AVCaptureDevice?
    
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.shared.queue")
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    private var pixelBufferHandler: ((CVPixelBuffer) -> Void)?
    
    private override init() {
        super.init()
        setupSession()
    }
    
    public func getSession() -> AVCaptureSession? {
        return session
    }
    
    private func setupSession() {
        session.beginConfiguration()
        
        // Preset photo pour un autofocus optimal
        session.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            print("[CameraManager] Erreur d'initialisation")
            return
        }
        
        session.addInput(input)
        self.input = input
        self.currentDevice = device
        
        // Configuration autofocus automatique puissant
        do {
            try device.lockForConfiguration()
            
            // Autofocus continu - le plus puissant
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                print("✅ Autofocus: continuousAutoFocus activé")
            }
            
            // Auto-exposition continue
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
                print("✅ Auto-exposition: continuousAutoExposure activé")
            }
            
            // Balance des blancs automatique
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                print("✅ Balance des blancs: continuousAutoWhiteBalance activé")
            }
            
            // Monitoring des changements de zone pour réactivité maximale
            device.isSubjectAreaChangeMonitoringEnabled = true
            print("✅ Subject area monitoring: activé")
            
            // Pas de restriction de plage pour flexibilité maximale
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .none
                print("✅ Focus range: aucune restriction")
            }
            
            device.unlockForConfiguration()
            
        } catch {
            print("❌ Failed to configure device: \(error)")
        }
        
        // Configuration video output
        if session.canAddOutput(videoOutput) {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            session.addOutput(videoOutput)
        }
        
        // Preview layer
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.cornerRadius = 46
        preview.masksToBounds = true
        self.previewLayer = preview
        
        session.commitConfiguration()
        
        // Observer pour les changements de zone (autofocus intelligent)
        setupSubjectAreaChangeNotification()
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
        // Réinitialise l'autofocus au centre quand la zone change
        guard let device = currentDevice else { return }
        
        queue.async {
            do {
                try device.lockForConfiguration()
                
                // Recentrer l'autofocus
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                
                // S'assurer que les modes continus sont toujours actifs
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                
                device.unlockForConfiguration()
                print("🔄 Autofocus recentré automatiquement")
                
            } catch {
                print("❌ Failed to reset autofocus: \(error)")
            }
        }
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
    
    func switchCamera() {
        session.beginConfiguration()
        
        // Supprimer l'observer de l'ancien device
        NotificationCenter.default.removeObserver(
            self,
            name: .AVCaptureDeviceSubjectAreaDidChange,
            object: currentDevice
        )
        
        // Supprimer tous les inputs existants
        for input in session.inputs {
            session.removeInput(input)
            print("✅ [SharedCameraManager] Input supprimé: \(input)")
        }
        
        guard let current = currentDevice else {
            print("❌ currentDevice is nil during camera switch")
            session.commitConfiguration()
            return
        }
        let newPosition: AVCaptureDevice.Position = (current.position == .back) ? .front : .back
        
        let previousType = self.input?.device.deviceType
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            previousType ?? .builtInWideAngleCamera,
            .builtInWideAngleCamera,
            .builtInTrueDepthCamera
        ]

        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: newPosition)

        guard let newDevice = discovery.devices.first,
              let newInput = try? AVCaptureDeviceInput(device: newDevice),
              session.canAddInput(newInput) else {
            print("❌ Switch camera failed")
            session.commitConfiguration()
            return
        }
        
        session.addInput(newInput)
        self.input = newInput
        self.currentDevice = newDevice
        
        // Configuration autofocus du nouveau device
        do {
            try newDevice.lockForConfiguration()
            
            if newDevice.isFocusModeSupported(.continuousAutoFocus) {
                newDevice.focusMode = .continuousAutoFocus
            }
            
            if newDevice.isExposureModeSupported(.continuousAutoExposure) {
                newDevice.exposureMode = .continuousAutoExposure
            }
            
            if newDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                newDevice.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            newDevice.isSubjectAreaChangeMonitoringEnabled = true
            
            if newDevice.isAutoFocusRangeRestrictionSupported {
                newDevice.autoFocusRangeRestriction = .none
            }
            
            newDevice.unlockForConfiguration()
            
        } catch {
            print("❌ Failed to configure new device: \(error)")
        }
        
        // Ajouter l'observer pour le nouveau device
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subjectAreaDidChange),
            name: .AVCaptureDeviceSubjectAreaDidChange,
            object: newDevice
        )
        
        if let connection = previewLayer?.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (newPosition == .front)
        }
        
        session.commitConfiguration()
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
