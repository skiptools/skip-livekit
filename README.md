# SkipLiveKit

SkipLiveKit provides a cross-platform [LiveKit](https://livekit.io) integration for [Skip](https://skip.dev) apps. It wraps the LiveKit [Swift SDK](https://github.com/livekit/client-sdk-swift) on iOS and the LiveKit [Android SDK](https://github.com/livekit/client-sdk-android) on Android behind a unified SwiftUI API, so you can add real-time video and audio rooms to your app without writing any platform-specific code.

## Setup

Add SkipLiveKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://source.skip.tools/skip-livekit.git", "0.0.0"..<"2.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "SkipLiveKit", package: "skip-livekit"),
    ]),
]
```

### Android Permissions

Your `AndroidManifest.xml` must include the following permissions for camera, microphone, and network access:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

### iOS Permissions

Add these keys to your `Darwin/AppName.xcconfig`:

```
INFOPLIST_KEY_NSCameraUsageDescription = "This app needs camera access for video calls";
INFOPLIST_KEY_NSMicrophoneUsageDescription = "This app needs microphone access for audio calls";
```

## Quick Start

The fastest way to add a video room to your app is with `LiveKitRoomView`. It handles connection, participant display, and media controls:

```swift
import SwiftUI
import SkipLiveKit

struct CallView: View {
    var body: some View {
        LiveKitRoomView(
            url: "wss://your-server.livekit.cloud",
            token: "your-jwt-access-token"
        )
    }
}
```

This renders a participant grid with camera, microphone, and hang-up buttons. It connects automatically when the view appears and handles disconnection when the user taps the hang-up button.

## Using LiveKitRoomManager

For more control over the room lifecycle, use `LiveKitRoomManager` directly:

```swift
import SwiftUI
import SkipLiveKit

struct MyRoomView: View {
    @StateObject var room = LiveKitRoomManager()

    var body: some View {
        VStack {
            Text("Room: \(room.roomName ?? "Not connected")")
            Text("State: \(room.connectionState.rawValue)")
            Text("Participants: \(room.participants.count)")

            if room.connectionState == .connected {
                HStack {
                    Button(room.isMicrophoneEnabled ? "Mute" : "Unmute") {
                        Task { try? await room.setMicrophoneEnabled(!room.isMicrophoneEnabled) }
                    }
                    Button(room.isCameraEnabled ? "Camera Off" : "Camera On") {
                        Task { try? await room.setCameraEnabled(!room.isCameraEnabled) }
                    }
                    Button("Leave") {
                        Task { await room.disconnect() }
                    }
                }
            }
        }
        .task {
            do {
                try await room.connect(
                    url: "wss://your-server.livekit.cloud",
                    token: "your-jwt-access-token"
                )
            } catch {
                print("Connection failed: \(error)")
            }
        }
    }
}
```

### LiveKitRoomManager API

| Property / Method | Type | Description |
|---|---|---|
| `connectionState` | `LiveKitConnectionState` | Current state: `.disconnected`, `.connecting`, `.connected`, `.reconnecting` |
| `participants` | `[LiveKitParticipantInfo]` | All participants including the local user |
| `roomName` | `String?` | The name of the connected room |
| `isCameraEnabled` | `Bool` | Whether the local camera is active |
| `isMicrophoneEnabled` | `Bool` | Whether the local microphone is active |
| `errorMessage` | `String?` | Error description if connection failed |
| `connect(url:token:)` | `async throws` | Connect to a LiveKit server |
| `disconnect()` | `async` | Disconnect from the current room |
| `setCameraEnabled(_:)` | `async throws` | Toggle the local camera |
| `setMicrophoneEnabled(_:)` | `async throws` | Toggle the local microphone |
| `updateParticipants()` | | Refresh the participant list from room state |

### LiveKitParticipantInfo

Each participant is represented as a simple value type:

```swift
public struct LiveKitParticipantInfo: Identifiable {
    public let id: String
    public let identity: String
    public let name: String
    public let isSpeaking: Bool
    public let isCameraEnabled: Bool
    public let isMicrophoneEnabled: Bool
    public let isLocal: Bool
}
```

## Development and Testing View

`LiveKitConnectView` provides a simple form for entering a server URL and token, useful during development:

```swift
import SkipLiveKit

struct DevView: View {
    var body: some View {
        NavigationStack {
            LiveKitConnectView { url, token in
                LiveKitRoomView(url: url, token: token)
            }
        }
    }
}
```

## Platform Implementation

SkipLiveKit is a [Skip Lite](https://skip.dev/docs/modes/#lite) module. The Swift source is transpiled to Kotlin for Android.

On iOS, SkipLiveKit uses the [LiveKit Swift SDK](https://github.com/livekit/client-sdk-swift) (`client-sdk-swift` v2.3+). Room management, participant tracking, and media control all go through the Swift `Room` class.

On Android, the transpiled Kotlin code uses the [LiveKit Android SDK](https://github.com/livekit/client-sdk-android) (`livekit-android` v2.24+). The `io.livekit.android.LiveKit.create(context)` factory creates a `Room` instance, and all participant and media APIs are accessed through the Android SDK's Kotlin API.

Platform differences in property types (such as Kotlin inline classes for participant IDs) are handled internally so the public API is identical on both platforms.

## Building

This project is a free Swift Package Manager module that uses the
[Skip](https://skip.dev) plugin to transpile Swift into Kotlin.

Building the module requires that Skip be installed using
[Homebrew](https://brew.sh) with `brew install skiptools/skip/skip`.
This will also install the necessary build prerequisites:
Kotlin, Gradle, and the Android build tools.

## Testing

The module can be tested using the standard `swift test` command
or by running the test target for the macOS destination in Xcode,
which will run the Swift tests as well as the transpiled
Kotlin JUnit tests in the Robolectric Android simulation environment.

Parity testing can be performed with `skip test`,
which will output a table of the test results for both platforms.

## License

This software is licensed under the
[GNU Lesser General Public License v3.0](https://spdx.org/licenses/LGPL-3.0-only.html),
with a [linking exception](https://spdx.org/licenses/LGPL-3.0-linking-exception.html)
to clarify that distribution to restricted environments (e.g., app stores) is permitted.
