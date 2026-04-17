import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var takePhoto = false
    @State private var showFlash = false
    @State private var switchCamera = false
    @State private var switchLens = false
    @State private var switchToLensIndex: Int?
    @State private var availableLenses: [LensInfo] = []
    @State private var currentLensIndex = 0
    @State private var showLensMenu = false
    @State private var isUsingFrontCamera = false
    @State private var frontCamera = false

    private var previewWidth: CGFloat {
        UIScreen.main.bounds.width - 10
    }

    private var previewHeight: CGFloat {
        previewWidth * 4 / 3
    }

    private var currentLensLabel: String {
        guard !availableLenses.isEmpty, currentLensIndex < availableLenses.count else {
            return "1x"
        }

        return availableLenses[currentLensIndex].zoomFactor
    }

    var body: some View {
        ZStack {
            previewSection
            flashOverlay
            controlsOverlay
            HiddenVolumeView()
                .frame(width: 0, height: 0)
                .opacity(0.01)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .onTapGesture {
            guard showLensMenu else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                showLensMenu = false
            }
        }
        .onAppear {
            SharedCameraManager.shared.start()

            if let defaultLensIndex = availableLenses.firstIndex(where: { $0.zoomFactor == "1x" }) {
                currentLensIndex = defaultLensIndex
            } else if !availableLenses.isEmpty {
                currentLensIndex = 0
            }

            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setActive(true)

            NotificationCenter.default.addObserver(
                forName: .volumeButtonPressed,
                object: nil,
                queue: .main
            ) { _ in
                takePhoto = true
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: .volumeButtonPressed, object: nil)
        }
    }

    private var previewSection: some View {
        VStack {
            Spacer()
                .frame(height: 80)

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
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
            .frame(width: previewWidth, height: previewHeight)
            .zIndex(1)

            Spacer()
        }
        .edgesIgnoringSafeArea(.all)
    }

    private var flashOverlay: some View {
        Rectangle()
            .foregroundColor(.black)
            .opacity(showFlash ? 0.8 : 0)
            .animation(.easeOut(duration: 0.15), value: showFlash)
            .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
            .frame(width: previewWidth, height: previewHeight)
            .offset(y: -103)
            .zIndex(3)
    }

    private var controlsOverlay: some View {
        VStack {
            Spacer()
            bottomBar
        }
        .zIndex(2)
    }

    private var bottomBar: some View {
        ZStack {
            HStack(alignment: .center, spacing: 26) {
                Spacer(minLength: 0)
                lensMenuButton
                    .disabled(frontCamera)
                captureButton
                rotateButton
                Spacer(minLength: 0)
            }
            .frame(height: 64)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 104)
    }

    private var lensMenuButton: some View {
        Button {
            guard !frontCamera else { return }

            withAnimation(.interpolatingSpring(stiffness: 90, damping: 18)) {
                showLensMenu.toggle()
            }
        } label: {
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: showLensMenu ? 40 : 32)
                    .fill(Color.white.opacity(0.1))
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 2)
                    .frame(width: 58, height: showLensMenu ? 180 : 58)
                    .animation(.interpolatingSpring(stiffness: 170, damping: 15), value: showLensMenu)
                    .opacity(frontCamera ? 0.3 : 1.0)

                if showLensMenu && !frontCamera {
                    VStack {
                        Spacer(minLength: 0)
                        ForEach(availableLenses.indices.reversed(), id: \.self) { index in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showLensMenu = false
                                }

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    switchToLensIndex = index
                                }
                            } label: {
                                Text(availableLenses[index].zoomFactor.isEmpty ? "\(index)x" : availableLenses[index].zoomFactor)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(index == currentLensIndex ? Color(red: 1.0, green: 0.3686, blue: 0.1294) : .white)
                                    .frame(height: 32)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                } else {
                    Text(currentLensLabel)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(frontCamera ? .gray : .white)
                        .opacity(frontCamera ? 0.6 : 1.0)
                }
            }
        }
        .frame(width: 58, height: showLensMenu ? 180 : 58)
        .onChange(of: frontCamera) { newValue in
            if newValue && showLensMenu {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLensMenu = false
                }
            }

            if let defaultLensIndex = availableLenses.firstIndex(where: { $0.zoomFactor == "1x" }) {
                currentLensIndex = defaultLensIndex
            } else {
                currentLensIndex = min(1, max(availableLenses.count - 1, 0))
            }
        }
    }

    private var captureButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
            takePhoto = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showFlash = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    showFlash = false
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                takePhoto = false
            }
        } label: {
            Image("btn")
                .resizable()
                .frame(width: 171, height: 62)
                .shadow(color: Color(red: 1.0, green: 0.3686, blue: 0.1294), radius: 5.3, x: 0, y: 0)
        }
    }

    private var rotateButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()

            frontCamera.toggle()
            SharedCameraManager.shared.switchCamera()

            if showLensMenu {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLensMenu = false
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 2)
                    .frame(width: 58, height: 58)

                Image("icon-rotate")
                    .resizable()
                    .frame(width: 30, height: 30)
                    .foregroundColor(.white)
            }
        }
        .frame(width: 58, height: 58)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)

        if #unavailable(iOS 13.0) {
            volumeView.showsRouteButton = false
        }

        volumeView.showsVolumeSlider = false
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

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
