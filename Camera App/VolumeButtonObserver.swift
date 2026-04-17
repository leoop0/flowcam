import AVFoundation
import MediaPlayer
import UIKit

final class VolumeButtonObserver {
    private let audioSession = AVAudioSession.sharedInstance()
    private var volumeView: MPVolumeView!
    private var initialVolume: Float = 0.5
    private var lastVolume: Float = 0.5

    var onVolumeButtonPressed: (() -> Void)?

    init() {
        setupVolumeObserver()
    }

    private func setupVolumeObserver() {
        do {
            try audioSession.setActive(true)
            initialVolume = audioSession.outputVolume
            lastVolume = initialVolume

            volumeView = MPVolumeView(frame: .zero)
            volumeView.alpha = 0.01

            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first {
                window.addSubview(volumeView)
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(volumeChanged),
                name: NSNotification.Name("AVSystemController_SystemVolumeDidChangeNotification"),
                object: nil
            )
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }

    @objc private func volumeChanged(notification: NSNotification) {
        let currentVolume = audioSession.outputVolume

        guard currentVolume != lastVolume else { return }

        lastVolume = currentVolume
        onVolumeButtonPressed?()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        volumeView?.removeFromSuperview()
    }
}
