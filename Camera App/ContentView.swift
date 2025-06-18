import UIKit
import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var takePhoto = false
    @State private var showLastPhoto = false
    @State private var isFlashOn = false
    @State private var cameraCoordinator: CameraView.Coordinator?
    @State private var switchCamera = false
    @State private var switchLens = false
    @State private var switchToLensIndex: Int? = nil
    @State private var availableLenses: [LensInfo] = []
    @State private var currentLensIndex = 0
    @State private var showLensMenu = false

    @State private var isUsingFrontCamera = false
    @State private var frontCamera = false
    
    // Nouvelle variable pour contrôler le background
    @State private var showBackgroundCamera = true
    
    // @State private var volumeObserver: Any? // plus utilisé
    
    var body: some View {
        ZStack {
            // Background Camera Feed (nouveau)
            if showBackgroundCamera {
                BlurredCameraBackgroundView()
                    .edgesIgnoringSafeArea(.all)
                    .zIndex(0) // Assure que c'est bien en arrière-plan
            }
            
            // Camera Preview (existant)
            VStack {
                Spacer()
                    .frame(height: 80)
                
                ZStack {
                    CameraView(
                        frontCamera: $frontCamera,
                        takePhoto: $takePhoto,
                        switchCamera: $switchCamera,
                        switchLens: $switchLens,
                        switchToLensIndex: $switchToLensIndex,
                        availableLenses: $availableLenses,
                        currentLensIndex: $currentLensIndex,
                        isUsingFrontCamera: $isUsingFrontCamera
                    )
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
                .frame(
                    width: UIScreen.main.bounds.width - 10,
                    height: (UIScreen.main.bounds.width - 10) * 4 / 3
                )
                .zIndex(1) // Au-dessus du background
                
                Spacer()
            }
            .edgesIgnoringSafeArea(.all)
            
            // Overlay UI (existant)
            VStack {
                Spacer()
                
                // Bottom Bar avec tous les boutons alignés
                bottomBar
            }
            .zIndex(2) // Au-dessus de tout
            
            // Invisible MPVolumeView to intercept volume button presses
            UIViewRepresentedVolumeView()
                .frame(width: 0, height: 0)
                .opacity(0.01)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .onTapGesture {
            // Fermer le menu si on tape ailleurs
            if showLensMenu {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLensMenu = false
                }
            }
        }
        .onAppear {
            print("🔍 ContentView appeared, isUsingFrontCamera: \(isUsingFrontCamera)")
            print("🔍 ContentView appeared, availableLenses: \(availableLenses.map { $0.zoomFactor })")

            if availableLenses.isEmpty {
                print("⚠️ Aucun objectif disponible détecté lors de l'apparition")
            }

            if !availableLenses.isEmpty {
                if let index = availableLenses.firstIndex(where: { $0.zoomFactor == "1x" }) {
                    currentLensIndex = index
                } else {
                    currentLensIndex = 0
                }
            }

            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setActive(true)

            NotificationCenter.default.addObserver(forName: .volumeButtonPressed, object: nil, queue: .main) { _ in
                takePhoto = true
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: .volumeButtonPressed, object: nil)
        }
    }
    
    // MARK: - Helper Methods
    
    // Computed property pour le texte du bouton de focale
    private var currentLensDisplayText: String {
        guard !availableLenses.isEmpty, currentLensIndex < availableLenses.count else { return "1x" }
        return availableLenses[currentLensIndex].zoomFactor
    }
    
    // MARK: - View Components
    

    @ViewBuilder
    private var bottomBar: some View {
        ZStack {
            HStack(alignment: .center) {
                lensMenuButton
                    .disabled(frontCamera)

                Spacer()
                captureButton
                Spacer()
                rotateButton
            }
            .padding(.horizontal, 30)
            .frame(height: 64)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 104)
    }

    
    @ViewBuilder
    private var lensMenuButton: some View {
        Button(action: {
            // Debug pour vérifier l'état de la caméra
            print("🔍 Bouton lens pressé - frontCamera: \(frontCamera)")
            
            // Ne pas ouvrir le menu si on est sur la caméra frontale
            guard !frontCamera else {
                print("❌ Action bloquée car caméra frontale active")
                return
            }
            
            print("✅ Ouverture du menu lens autorisée")
            withAnimation(.interpolatingSpring(stiffness: 90, damping: 18)) {
                showLensMenu.toggle()
            }
        }) {
            ZStack(alignment: .center) {
                Image(showLensMenu ? "btn-bg-lg" : "btn-bg")
                    .resizable()
                    .frame(width: 64, height: showLensMenu ? 180 : 64)
                    .animation(.interpolatingSpring(stiffness: 170, damping: 15), value: showLensMenu)
                    .opacity(frontCamera ? 0.3 : 1.0)
                
                if showLensMenu && !frontCamera {
                    VStack {
                        ForEach(availableLenses.indices.reversed(), id: \.self) { index in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showLensMenu = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    switchToLensIndex = index
                                }
                            }) {
                                Text(availableLenses[index].zoomFactor.isEmpty ? "\(index)x" : availableLenses[index].zoomFactor)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundColor(index == currentLensIndex ? .blue : .white)
                                    .frame(height: 50)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(width: 64, height: 180)
                } else {
                    Text(currentLensDisplayText)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(frontCamera ? .gray : .white)
                        .opacity(frontCamera ? 0.6 : 1.0)
                }
            }
        }
        .frame(width: 64, height: showLensMenu ? 180 : 64)
        .onChange(of: frontCamera) { newValue in
            print("🔄 frontCamera changé: \(newValue)")
            
            // Fermer le menu automatiquement si on passe à la caméra frontale
            if newValue && showLensMenu {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLensMenu = false
                }
            }
            
            // Forcer l'affichage sur 1x à chaque changement de caméra
            if let index = availableLenses.firstIndex(where: { $0.zoomFactor == "1x" }) {
                currentLensIndex = index
            } else {
                currentLensIndex = 1 // fallback sur l'index 1 (généralement la lentille standard)
            }
        }

        // SUPPRIMÉES : les lignes .disabled(frontCamera) et .allowsHitTesting(!frontCamera)
    }


    
    
    @ViewBuilder
    private var captureButton: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
            takePhoto = true
        }) {
            RoundedRectangle(cornerRadius: 67)
                .fill(Color.white)
                .frame(width: 189, height: 58)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 67)
                        .stroke(Color.black.opacity(0.1), lineWidth: 2)
                )
        }
    }
    
    @ViewBuilder
    private var rotateButton: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()

            frontCamera.toggle()
            SharedCameraManager.shared.switchCamera()

            // Fermer le menu si ouvert
            if showLensMenu {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLensMenu = false
                }
            }
        }) {
            ZStack {
                Image("btn-bg")
                    .resizable()
                    .frame(width: 64, height: 64)

                Image("icon-rotate")
                    .resizable()
                    .frame(width: 30, height: 30)
            }
            .frame(width: 64, height: 64)
        }
    }
}

// Ajout de la PreferenceKey pour le frame
struct LensButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

import MediaPlayer

struct UIViewRepresentedVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        if #available(iOS 13.0, *) {
            // AVRoutePickerView can be used instead, or simply avoid setting the property
        } else {
            volumeView.showsRouteButton = false
        }
        volumeView.showsVolumeSlider = false
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Volume Button Interception via UIWindow
class VolumeButtonWindow: UIWindow {
    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
        guard let touches = event.allTouches else { return }
        if touches.contains(where: { $0.type.rawValue == 0x04 }) {
            NotificationCenter.default.post(name: .volumeButtonPressed, object: nil)
        }
    }
}

extension Notification.Name {
    static let volumeButtonPressed = Notification.Name("VolumeButtonPressed")
}
