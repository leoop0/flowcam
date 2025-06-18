import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

struct BlurredCameraBackgroundView: View {
    @State private var blurredImage: UIImage?
    private let context = CIContext()
    private let blurFilter = CIFilter.gaussianBlur()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let uiImage = blurredImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity)
                } else {
                    Color.black
                }

                // Optionnel : un overlay foncé par-dessus
                Color.black.opacity(0.4)
            }
            .onAppear {
                
                
                SharedCameraManager.shared.setPixelBufferHandler { buffer in
                    let isFront = SharedCameraManager.shared.currentDevice?.position == .front
                    let ciImage = CIImage(cvPixelBuffer: buffer)
                        .oriented(forExifOrientation: isFront ? 5 : 6)
                    

                    blurFilter.inputImage = ciImage
                    blurFilter.radius = 26

                    guard let outputImage = blurFilter.outputImage,
                          let cgImage = context.createCGImage(outputImage, from: ciImage.extent)
                    else { return }

                    let uiImage = UIImage(cgImage: cgImage)
                    DispatchQueue.main.async {
                        self.blurredImage = uiImage
                    }
                }

                SharedCameraManager.shared.start()
                
                
            }
            .onDisappear {
                SharedCameraManager.shared.setPixelBufferHandler { _ in } // coupe le handler en 1er
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    SharedCameraManager.shared.stop() // arrête la session après un léger délai
                }
            }        }
        .ignoresSafeArea()
    }
}
