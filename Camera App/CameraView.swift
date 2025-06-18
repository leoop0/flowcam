//
//  CameraView.swift
//  Camera App
//
//  Created by Léo Frati on 30/05/2025.
//

import SwiftUI
import AVFoundation
import CoreImage
import ImageIO

struct LensInfo {
    let deviceType: AVCaptureDevice.DeviceType
    let displayName: String
    let zoomFactor: String
    let isDigitalZoom: Bool // Pour distinguer le zoom numérique
    
    static func getAvailableLenses(position: AVCaptureDevice.Position) -> [LensInfo] {
        var lenses: [LensInfo] = []
        
        if position == .back {
            // iPhone 15 Pro - Caméras arrière
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
                .builtInTelephotoCamera
            ]
            
            for deviceType in deviceTypes {
                if let _ = AVCaptureDevice.default(deviceType, for: .video, position: position) {
                    switch deviceType {
                    case .builtInUltraWideCamera:
                        lenses.append(LensInfo(deviceType: deviceType, displayName: "Ultra Wide", zoomFactor: ".5x", isDigitalZoom: false))
                    case .builtInWideAngleCamera:
                        lenses.append(LensInfo(deviceType: deviceType, displayName: "Wide", zoomFactor: "1x", isDigitalZoom: false))
                        // Ajout d'une lentille numérique 2x si pas de téléphoto
                        if position == .back {
                            let hasTelephoto = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: position) != nil
                            if !hasTelephoto {
                                lenses.append(LensInfo(deviceType: deviceType, displayName: "Wide 2x", zoomFactor: "2x", isDigitalZoom: true))
                            }
                        }
                    case .builtInTelephotoCamera:
                        lenses.append(LensInfo(deviceType: deviceType, displayName: "Telephoto", zoomFactor: "3x", isDigitalZoom: false))
                    default:
                        break
                    }
                }
            }
        } else {
            // Caméras frontales
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInWideAngleCamera,
                .builtInTrueDepthCamera
            ]
            
            for deviceType in deviceTypes {
                if let _ = AVCaptureDevice.default(deviceType, for: .video, position: position) {
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
        // Correction: fallback pour zoomFactor inconnu
        let validatedLenses = lenses.enumerated().map { index, lens in
            let zoom = lens.zoomFactor.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = "\(index + 1)x"
            return zoom.isEmpty ? LensInfo(deviceType: lens.deviceType, displayName: lens.displayName, zoomFactor: fallback, isDigitalZoom: lens.isDigitalZoom) : lens
        }
        return validatedLenses
    }
}


struct CameraView: UIViewControllerRepresentable {
    @Binding var frontCamera: Bool
    @Binding var takePhoto: Bool
    @Binding var switchCamera: Bool
    @Binding var switchLens: Bool
    @Binding var switchToLensIndex: Int? // Nouveau binding pour changement direct
    @Binding var availableLenses: [LensInfo]
    @Binding var currentLensIndex: Int
    @Binding var isUsingFrontCamera: Bool
    
    class Coordinator: NSObject, AVCapturePhotoCaptureDelegate {
        var parent: CameraView
        private var frontCamera: Binding<Bool>
        var output: AVCapturePhotoOutput?
        var session: AVCaptureSession?
        var currentInput: AVCaptureDeviceInput?
        let context = CIContext()
        private var isSwitching = false
        private var cachedLenses: [LensInfo] = []
        private var localLensIndex: Int = 0 // Variable locale pour suivre l'état réel
        
        init(frontCamera: Binding<Bool>, parent: CameraView) {
            self.parent = parent
            self.frontCamera = frontCamera
            self.output = AVCapturePhotoOutput()
            self.output?.isHighResolutionCaptureEnabled = true
            let sharedSession = SharedCameraManager.shared.session
            self.session = sharedSession
            self.output = AVCapturePhotoOutput()
            self.output?.isHighResolutionCaptureEnabled = true
            if sharedSession.canAddOutput(self.output!) {
                sharedSession.addOutput(self.output!)
            }
        }
        
        func updateAvailableLenses() {
            let position: AVCaptureDevice.Position = parent.isUsingFrontCamera ? .front : .back
            let lenses = LensInfo.getAvailableLenses(position: position)
            let validatedLenses = lenses.map { lens in
                if lens.zoomFactor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return LensInfo(deviceType: lens.deviceType, displayName: lens.displayName, zoomFactor: "?", isDigitalZoom: lens.isDigitalZoom)
                }
                return lens
            }
            // 🧪 Debug output
            print("🧪 Nombre de lentilles disponibles: \(validatedLenses.count)")
            for (index, lens) in validatedLenses.enumerated() {
                print("📷 Lentille \(index): \(lens.displayName) - \(lens.zoomFactor)")
            }

            // Mettre à jour le cache local
            cachedLenses = validatedLenses

            // Trouver l'index du Wide (1x) pour démarrer dessus
            let wideIndex = validatedLenses.firstIndex { $0.zoomFactor == "1x" && !$0.isDigitalZoom } ?? 0

            DispatchQueue.main.async {
                self.parent.availableLenses = validatedLenses
                self.parent.currentLensIndex = wideIndex
                self.localLensIndex = wideIndex
                print("📷 Lentilles disponibles pour \(position == .front ? "frontale" : "arrière"):")
                for (index, lens) in validatedLenses.enumerated() {
                    print("  \(index): \(lens.displayName) (\(lens.zoomFactor))")
                }
                print("🎯 Démarrage sur index \(wideIndex) (\(validatedLenses[wideIndex].displayName))")
            }
        }

        
        func switchToLens(at index: Int) {
            guard !isSwitching else {
                print("🔄 Switch lens déjà en cours, ignoré")
                return
            }

            guard let session = session else {
                print("❌ Session non disponible pour switch lens")
                return
            }

            let lenses = cachedLenses
            guard index < lenses.count else {
                print("❌ Index de lentille invalide: \(index)")
                return
            }

            // Si on est déjà sur cette lentille, ne rien faire
            guard index != localLensIndex else {
                print("ℹ️ Déjà sur la lentille \(lenses[index].displayName)")
                return
            }

            isSwitching = true

            let currentIndex = localLensIndex
            let targetLens = lenses[index]
            let currentLens = lenses[currentIndex]

            // Mettre à jour IMMÉDIATEMENT la variable locale
            localLensIndex = index

            let position: AVCaptureDevice.Position = parent.isUsingFrontCamera ? .front : .back

            // Ajout debug: print avant recherche du nouvel appareil
            print("🔍 Tentative d'accès à la lentille: \(targetLens.deviceType) position: \(position)")
            if let testDevice = AVCaptureDevice.default(targetLens.deviceType, for: .video, position: position) {
                print("✅ Appareil trouvé: \(testDevice.localizedName)")
            } else {
                print("❌ Appareil introuvable pour type: \(targetLens.deviceType.rawValue)")
            }

            print("🔄 Switch lens direct de \(currentLens.displayName) vers \(targetLens.displayName)")
            print("🔄 Index local: \(currentIndex) → \(index)")

            // Arrêter la session AVANT la configuration
            session.stopRunning()

            session.beginConfiguration()

            // Supprimer tous les inputs vidéo existants
            for input in session.inputs {
                session.removeInput(input)
                print("✅ Input supprimé: \(input)")
            }

            // Trouver le nouveau device
            guard let newDevice = AVCaptureDevice.default(targetLens.deviceType, for: .video, position: position),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                print("❌ Impossible de créer le nouvel input lens")
                session.commitConfiguration()
                session.startRunning()

                // Remettre l'ancien index local en cas d'erreur
                localLensIndex = currentIndex
                isSwitching = false
                return
            }

            // Ajouter le nouvel input
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                currentInput = newInput
                print("✅ Nouvel input lens ajouté: \(targetLens.displayName)")

                // Configuration du device
                do {
                    try newDevice.lockForConfiguration()
                    newDevice.automaticallyAdjustsVideoHDREnabled = false

                    // Si c'est du zoom numérique, appliquer le zoom
                    if targetLens.isDigitalZoom && targetLens.zoomFactor == "2x" {
                        newDevice.videoZoomFactor = 2.0
                    }

                    newDevice.unlockForConfiguration()
                } catch {
                    print("⚠️ Erreur configuration lens : \(error)")
                }

                session.commitConfiguration()
                session.startRunning()
                print("✅ Configuration lens terminée")

                // Synchroniser l'UI avec l'état local
                DispatchQueue.main.async {
                    self.parent.currentLensIndex = index
                    print("🔄 Index UI synchronisé: \(index) (\(targetLens.displayName))")
                }

                // Attendre que la session soit stabilisée
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.isSwitching = false
                        print("✅ Switch lens direct terminé - Index final: \(self.localLensIndex)")
                    }
                }
            } else {
                print("❌ Impossible d'ajouter le nouvel input lens")
                session.commitConfiguration()
                session.startRunning()

                // Remettre l'ancien index local en cas d'erreur
                localLensIndex = currentIndex
                isSwitching = false
            }
        }

        
        func switchLens() {
            guard !isSwitching else {
                print("🔄 Switch lens déjà en cours, ignoré")
                return
            }
            
            guard let session = session else {
                print("❌ Session non disponible pour switch lens")
                return
            }
            
            let lenses = cachedLenses
            guard !lenses.isEmpty else {
                print("❌ Aucune lentille disponible dans le cache")
                return
            }
            
            isSwitching = true
            
            // Utiliser la variable locale pour le calcul
            let currentIndex = localLensIndex
            let nextIndex = (currentIndex + 1) % lenses.count
            let nextLens = lenses[nextIndex]
            let currentLens = lenses[currentIndex]
            
            // Mettre à jour IMMÉDIATEMENT la variable locale
            localLensIndex = nextIndex
            
            let position: AVCaptureDevice.Position = parent.isUsingFrontCamera ? .front : .back
            
            print("🔄 Switch lens de \(currentLens.displayName) vers \(nextLens.displayName)")
            print("🔄 Index local: \(currentIndex) → \(nextIndex)")
            
            session.beginConfiguration()
            
            // Retirer l'input actuel
            if let currentInput = currentInput {
                session.removeInput(currentInput)
                print("✅ Input lens retiré")
            }
            
            // Trouver le nouveau device
            guard let newDevice = AVCaptureDevice.default(nextLens.deviceType, for: .video, position: position),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                print("❌ Impossible de créer le nouvel input lens")
                session.commitConfiguration()
                
                // Remettre l'ancien index local en cas d'erreur
                localLensIndex = currentIndex
                isSwitching = false
                return
            }
            
            // Ajouter le nouvel input
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                currentInput = newInput
                print("✅ Nouvel input lens ajouté: \(nextLens.displayName)")
                
                // Configuration du device
                do {
                    try newDevice.lockForConfiguration()
                    newDevice.automaticallyAdjustsVideoHDREnabled = false
                    newDevice.unlockForConfiguration()
                } catch {
                    print("⚠️ Erreur configuration lens : \(error)")
                }
                
                session.commitConfiguration()
                print("✅ Configuration lens terminée")
                
                // Synchroniser l'UI avec l'état local
                DispatchQueue.main.async {
                    self.parent.currentLensIndex = nextIndex
                    print("🔄 Index UI synchronisé: \(nextIndex) (\(nextLens.displayName))")
                }
                
                // Attendre que la session soit stabilisée
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.parent.switchLens = false
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.isSwitching = false
                        print("✅ Switch lens terminé - Index final: \(self.localLensIndex)")
                    }
                }
            } else {
                print("❌ Impossible d'ajouter le nouvel input lens")
                session.commitConfiguration()
                
                // Remettre l'ancien index local en cas d'erreur
                localLensIndex = currentIndex
                DispatchQueue.main.async {
                    self.parent.switchLens = false
                }
                isSwitching = false
            }
        }
        
        func switchCamera() {
            // Prévenir les appels multiples
            guard !isSwitching else {
                print("🔄 Switch caméra déjà en cours, ignoré")
                return
            }
            
            guard let session = session else {
                print("❌ Session non disponible")
                return
            }
            
            isSwitching = true
            
            // Obtenir la position actuelle directement depuis le device
            let currentPosition = currentInput?.device.position ?? .back
            let currentlyUsingFront = (currentPosition == .front)
            
            print("🔄 Switch caméra - Position actuelle du device: \(currentPosition == .front ? "frontale" : "arrière")")
            print("🔄 État parent: \(parent.isUsingFrontCamera ? "frontale" : "arrière")")
            
            session.beginConfiguration()
            
            // Retirer l'input actuel
            if let currentInput = currentInput {
                session.removeInput(currentInput)
                print("✅ Input retiré")
            }
            
            // Déterminer la nouvelle position de caméra (inverse de l'actuelle)
            let newPosition: AVCaptureDevice.Position = currentlyUsingFront ? .back : .front
            print("🎯 Nouvelle position: \(newPosition == .back ? "arrière" : "frontale")")
            
            // Trouver le device approprié
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                print("❌ Impossible de créer le nouvel input")
                session.commitConfiguration()
                isSwitching = false
                return
            }
            
            // Ajouter le nouvel input
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                currentInput = newInput
                print("✅ Nouvel input ajouté")
                
                // Configuration du device
                do {
                    try newDevice.lockForConfiguration()
                    newDevice.automaticallyAdjustsVideoHDREnabled = false
                    newDevice.unlockForConfiguration()
                } catch {
                    print("⚠️ Erreur configuration appareil : \(error)")
                }
                
                // Synchroniser l'état avec la position réelle du device
                let newState = (newPosition == .front)
                DispatchQueue.main.async {
                    self.parent.isUsingFrontCamera = newState
                    self.frontCamera.wrappedValue = newState
                    print("🔄 État synchronisé avec device: \(newState ? "frontale" : "arrière")")
                    
                    // Mettre à jour les lentilles disponibles pour la nouvelle position
                    self.updateAvailableLenses()
                    
                    // Remettre switchCamera à false ici, après le traitement
                    self.parent.switchCamera = false
                    
                    // Attendre un peu avant de réautoriser les switches
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isSwitching = false
                        print("✅ Switch caméra terminé, prêt pour le prochain")
                    }
                }
            } else {
                print("❌ Impossible d'ajouter le nouvel input")
                DispatchQueue.main.async {
                    self.parent.switchCamera = false
                }
                isSwitching = false
            }
            
            session.commitConfiguration()
            print("✅ Configuration caméra terminée")
        }
        
        func capturePhoto() {
            guard let output = self.output else { return }
            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true
            
            // Configuration pour éviter les freezes
            if #available(iOS 13.0, *) {
                settings.photoQualityPrioritization = .speed
            } else {
                settings.isAutoStillImageStabilizationEnabled = false
            }
            
            self.output?.capturePhoto(with: settings, delegate: self)
        }
        
        func photoOutput(_ output: AVCapturePhotoOutput,
                         didFinishProcessingPhoto photo: AVCapturePhoto,
                         error: Error?) {
            guard let cgImage = photo.cgImageRepresentation() else { return }
            
            var ciImage = CIImage(cgImage: cgImage)
            
            // Correction de l'orientation pour la caméra frontale
            let orientation = UIDevice.current.orientation
            let isUsingFront = parent.isUsingFrontCamera
            
            switch orientation {
            case .portrait:
                ciImage = ciImage.oriented(isUsingFront ? CGImagePropertyOrientation.leftMirrored : CGImagePropertyOrientation.right)
            case .portraitUpsideDown:
                ciImage = ciImage.oriented(isUsingFront ? CGImagePropertyOrientation.rightMirrored : CGImagePropertyOrientation.left)
            case .landscapeLeft:
                ciImage = ciImage.oriented(isUsingFront ? CGImagePropertyOrientation.downMirrored : CGImagePropertyOrientation.up)
            case .landscapeRight:
                ciImage = ciImage.oriented(isUsingFront ? CGImagePropertyOrientation.upMirrored : CGImagePropertyOrientation.down)
            default:
                ciImage = ciImage.oriented(isUsingFront ? CGImagePropertyOrientation.leftMirrored : CGImagePropertyOrientation.right)
            }
            
            // Traitement en arrière-plan
            DispatchQueue.global(qos: .userInitiated).async {
                // Ensure correct image is passed to applyZerocamStyle
                let processedImage = self.applyZerocamStyle(to: ciImage)
                print("✅ Zerocam style applied")
                if let jpegData = self.context.jpegRepresentation(
                    of: processedImage,
                    colorSpace: CGColorSpaceCreateDeviceRGB(),
                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]
                ) {
                    DispatchQueue.main.async {
                        UIImageWriteToSavedPhotosAlbum(UIImage(data: jpegData)!, nil, nil, nil)
                    }
                }
            }
        }
        
        private func applyZerocamStyle(to image: CIImage) -> CIImage {
            // Preset medium par défaut (comme avant avec intensity = 0.5)
            let medium = (saturation: 1.08, contrast: 1.07, brightness: 0.01, grain: 0.04)
            
            var result = image
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: medium.saturation,
                    kCIInputContrastKey: medium.contrast,
                    kCIInputBrightnessKey: medium.brightness
                ])
            
            // Ajout du grain medium
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
        
        private func verifySessionState() {
            guard let session = session else { return }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !session.isRunning {
                    print("⚠️ Session arrêtée, redémarrage...")
                    session.startRunning()
                }
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
                guard let previewLayer = previewLayer else { return }

                previewLayer.frame = view.bounds
                previewLayer.cornerRadius = 46
                previewLayer.masksToBounds = true
            }
        }

        let controller = CameraViewController()
        controller.view.backgroundColor = .black

        guard let previewLayer = SharedCameraManager.shared.getPreviewLayer() else {
            print("❌ Aucun previewLayer trouvé depuis SharedCameraManager")
            return controller
        }

        controller.previewLayer = previewLayer
        controller.view.layer.addSublayer(previewLayer)

        // Ensure available lenses are loaded at initialization
        context.coordinator.updateAvailableLenses()

        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Synchronize frontCamera binding with isUsingFrontCamera
        // Commentez cette ligne qui cause le problème
        // if frontCamera != isUsingFrontCamera {
        //     DispatchQueue.main.async {
        //         self.frontCamera = self.isUsingFrontCamera
        //     }
        // }

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
        
        // Nouveau: changement direct de lentille
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
