//
//  VolumeButtonObserver.swift
//  Camera App
//
//  Created by Léo Frati on 16/06/2025.
//

import AVFoundation
import MediaPlayer

class VolumeButtonObserver {
    private var audioSession = AVAudioSession.sharedInstance()
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

            // Cache le slider de volume système
            volumeView = MPVolumeView(frame: .zero)
            volumeView.alpha = 0.01
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first {
                window.addSubview(volumeView)
            }

            // Observe les changements de volume
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(volumeChanged),
                name: NSNotification.Name("AVSystemController_SystemVolumeDidChangeNotification"),
                object: nil
            )
        } catch {
            print("❌ Erreur activation audio session: \(error)")
        }
    }

    @objc private func volumeChanged(notification: NSNotification) {
        let currentVolume = audioSession.outputVolume

        if currentVolume != lastVolume {
            lastVolume = currentVolume
            onVolumeButtonPressed?()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        volumeView?.removeFromSuperview()
    }
}
