# Flowcam

Minimalist iPhone camera app built with SwiftUI and AVFoundation.

Website: [flowcam.vercel.app](https://flowcam.vercel.app/)

## Overview

Flowcam is a lightweight camera app focused on a clean shooting experience.
The project is built natively for iOS with SwiftUI for the interface and AVFoundation for camera capture.

The app keeps the experience simple:

- fast photo capture
- front and back camera switching
- lens selection when available
- hardware volume button capture
- direct save to the user's photo library

## Features

- Clean, minimal camera UI
- Native camera preview powered by `AVCaptureSession`
- Support for multiple rear lenses when the device exposes them
- Front camera support
- Capture feedback flash overlay
- Photo saving to the Photos library
- Local-only behavior with no backend dependency

## Tech Stack

- Swift
- SwiftUI
- AVFoundation
- Core Image
- Photos framework

## Project Structure

```text
Camera App/
├── Camera App/             # App source files
├── Camera AppTests/        # Unit tests
├── Camera AppUITests/      # UI tests
└── Camera App.xcodeproj/   # Xcode project
```

## Getting Started

### Requirements

- Xcode 16 or newer
- iOS SDK supported by the current project configuration
- A physical iPhone is recommended for camera testing
- An Apple ID signed into Xcode

### Run locally

1. Clone the repository.
2. Open `Camera App.xcodeproj` in Xcode.
3. Open the project signing settings in Xcode.
4. Select your own Apple account and signing team.
5. If needed, change the bundle identifier to something unique for your device.
6. Select an iPhone device or simulator.
7. Build and run the `Camera App` scheme.

For real camera testing, use a physical device and make sure camera and photo library permissions are granted.

### Installing on a real device without a paid Apple Developer account

You do not need the repository owner to pay for an Apple Developer subscription in order to run Flowcam on your own iPhone.

What you do need:

- a Mac
- Xcode
- your own Apple ID added in Xcode

With a free Apple ID, you can build and sign the app for your own device from Xcode.

Notes:

- free provisioning is meant for personal testing and has Apple-imposed limits
- you may need to trust the developer profile on your device
- if signing fails, set your own unique bundle identifier in Xcode before building

## Permissions

Flowcam currently requests:

- Camera access
- Photo library add access

## Privacy

Flowcam is designed as a local-first app.
Captured media is saved to the user's photo library, and the project does not require any server or cloud service to function.

## License

This project is licensed under the GNU GPL v3.0.

That means derivative redistributed versions must also remain open source under the GPL.

## Contributing

Issues and pull requests are welcome.

If you want to contribute, please keep changes focused and easy to review.
