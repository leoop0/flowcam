//
//  CameraView.swift
//  Camera App
//
//  Created by Léo Frati on 30/05/2025.
//

import SwiftUI
import AVFoundation
import CoreImage

struct CameraView: UIViewControllerRepresentable {
    @Binding var takePhoto: Bool
    @Binding var presetValue: Double // 0=low, 0.5=medium, 1=strong
    
    class Coordinator: NSObject, AVCapturePhotoCaptureDelegate {
        var parent: CameraView
        var output: AVCapturePhotoOutput?
        let context = CIContext()
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func capturePhoto() {
            guard let output = self.output else { return }
            let settings = AVCapturePhotoSettings()
   
            output.capturePhoto(with: settings, delegate: self)
        }
        
        func photoOutput(_ output: AVCapturePhotoOutput,
                         didFinishProcessingPhoto photo: AVCapturePhoto,
                         error: Error?) {
            guard let cgImage = photo.cgImageRepresentation() else { return }
            
            let ciImage = CIImage(cgImage: cgImage)
            let processedImage = applyStopsStyle(to: ciImage, intensity: parent.presetValue)
            
            if let jpegData = context.jpegRepresentation(
                of: processedImage,
                colorSpace: CGColorSpaceCreateDeviceRGB(),
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.92]
            ) {
                UIImageWriteToSavedPhotosAlbum(UIImage(data: jpegData)!, nil, nil, nil)
            }
        }
        
        private func applyStopsStyle(to image: CIImage, intensity: Double) -> CIImage {
            // Définition des presets
            let low = (saturation: 1.0, contrast: 1.0, brightness: 0.0, grain: 0.01)
            let medium = (saturation: 1.08, contrast: 1.07, brightness: 0.01, grain: 0.04)
            let strong = (saturation: 1.2, contrast: 1.3, brightness: 0.02, grain: 0.08)
            
            var sat: Double
            var con: Double
            var bri: Double
            var gra: Double
            
            if intensity <= 0.5 {
                let t = intensity / 0.5
                sat = low.saturation + (medium.saturation - low.saturation) * t
                con = low.contrast + (medium.contrast - low.contrast) * t
                bri = low.brightness + (medium.brightness - low.brightness) * t
                gra = low.grain + (medium.grain - low.grain) * t
            } else {
                let t = (intensity - 0.5) / 0.5
                sat = medium.saturation + (strong.saturation - medium.saturation) * t
                con = medium.contrast + (strong.contrast - medium.contrast) * t
                bri = medium.brightness + (strong.brightness - medium.brightness) * t
                gra = medium.grain + (strong.grain - medium.grain) * t
            }
            
            var result = image
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: sat,
                    kCIInputContrastKey: con,
                    kCIInputBrightnessKey: bri
                ])
            
            // Ajout du grain
            if let noise = CIFilter(name: "CIRandomGenerator")?.outputImage?
                .cropped(to: result.extent)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0, y: 0, z: 0, w: gra),
                    "inputGVector": CIVector(x: 0, y: 0, z: 0, w: gra),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0, w: gra),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                ]) {
                result = CIFilter(name: "CIAdditionCompositing", parameters: [
                    kCIInputImageKey: noise,
                    kCIInputBackgroundImageKey: result
                ])?.outputImage ?? result
            }
            
            return result
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        let session = AVCaptureSession()
        session.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return controller
        }
        session.addInput(input)
        
        do {
            try device.lockForConfiguration()
            device.automaticallyAdjustsVideoHDREnabled = false
            device.unlockForConfiguration()
        } catch {
            print("Erreur configuration appareil : \(error)")
        }
        
        let output = AVCapturePhotoOutput()
        session.addOutput(output)
        context.coordinator.output = output
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        let screenBounds = UIScreen.main.bounds
        let screenWidth = screenBounds.width
        let previewWidth = screenWidth
        let previewHeight = screenWidth * 4 / 3
        let previewY = max((screenBounds.height - previewHeight) / 2, 0)
        let previewFrame = CGRect(x: 0, y: previewY, width: previewWidth, height: previewHeight)

        previewLayer.frame = previewFrame
        
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
        view.layer.addSublayer(previewLayer)
        controller.view = view
        
        session.startRunning()
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if takePhoto {
            context.coordinator.capturePhoto()
            DispatchQueue.main.async {
                self.takePhoto = false
            }
        }
    }
}
