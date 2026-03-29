// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import Foundation
import SwiftUI
import OSLog
#if SKIP
import io.livekit.android.__
import io.livekit.android.audio.__
import io.livekit.android.room.__
import io.livekit.android.room.participant.__
import io.livekit.android.room.track.__
import com.twilio.audioswitch.AudioDevice
#else
import LiveKit
#endif

private let logger: os.Logger = os.Logger(subsystem: "skip.livekit", category: "SkipLiveKit")

// MARK: - Connection State

/// Platform-independent connection state.
public enum LiveKitConnectionState: String {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

// MARK: - Connection Quality

/// Platform-independent connection quality for a participant.
public enum LiveKitConnectionQuality: String {
    case unknown
    case lost
    case poor
    case good
    case excellent
}

// MARK: - Data Reliability

/// Whether data messages are sent reliably (TCP-like) or lossy (UDP-like).
public enum LiveKitDataReliability {
    case reliable
    case lossy
}

// MARK: - Participant Info

/// Platform-independent representation of a room participant.
public struct LiveKitParticipantInfo: Identifiable {
    public let id: String
    public let identity: String
    public let name: String
    public let metadata: String?
    public let isSpeaking: Bool
    public let audioLevel: Float
    public let connectionQuality: LiveKitConnectionQuality
    public let isCameraEnabled: Bool
    public let isMicrophoneEnabled: Bool
    public let isScreenShareEnabled: Bool
    public let isLocal: Bool
}

// MARK: - Room Manager

/// Observable room manager that provides a unified API for connecting to
/// LiveKit rooms on both iOS and Android.
///
/// Usage:
/// ```swift
/// @StateObject var room = LiveKitRoomManager()
///
/// // Connect
/// try await room.connect(url: "wss://your-server.livekit.cloud", token: "your-token")
///
/// // Enable camera and microphone
/// try await room.setCameraEnabled(true)
/// try await room.setMicrophoneEnabled(true)
///
/// // Disconnect
/// await room.disconnect()
/// ```
public class LiveKitRoomManager: ObservableObject {
    @Published public var connectionState: LiveKitConnectionState = .disconnected
    @Published public var participants: [LiveKitParticipantInfo] = []
    @Published public var errorMessage: String?
    @Published public var isCameraEnabled: Bool = false
    @Published public var isMicrophoneEnabled: Bool = false
    @Published public var isScreenShareEnabled: Bool = false
    @Published public var isSpeakerphoneEnabled: Bool = true
    @Published public var isFrontCamera: Bool = true
    @Published public var roomName: String?
    @Published public var roomMetadata: String?

    /// Called when a data message is received from another participant.
    /// Parameters are: (senderIdentity, data, topic).
    public var onDataReceived: ((String?, Data, String?) -> Void)?

    #if SKIP
    var nativeRoom: io.livekit.android.room.Room? = nil
    #else
    var nativeRoom: Room?
    #endif

    public init() {}

    /// Connect to a LiveKit room.
    public func connect(url: String, token: String) async throws {
        connectionState = .connecting
        errorMessage = nil

        do {
            #if SKIP
            let rm = io.livekit.android.LiveKit.create(ProcessInfo.processInfo.androidContext)
            rm.connect(url, token)
            self.nativeRoom = rm
            roomName = rm.name
            #else
            let rm = Room()
            try await rm.connect(url: url, token: token)
            self.nativeRoom = rm
            roomName = rm.name
            #endif

            connectionState = .connected
            roomMetadata = rm.metadata
            updateParticipants()
            logger.info("Connected to room: \(self.roomName ?? "unknown")")
        } catch {
            connectionState = .disconnected
            errorMessage = error.localizedDescription
            logger.error("Failed to connect: \(error.localizedDescription)")
            throw error
        }
    }

    /// Disconnect from the current room.
    public func disconnect() async {
        #if SKIP
        nativeRoom?.disconnect()
        #else
        await nativeRoom?.disconnect()
        #endif

        nativeRoom = nil
        connectionState = .disconnected
        participants = []
        isCameraEnabled = false
        isMicrophoneEnabled = false
        isScreenShareEnabled = false
        isFrontCamera = true
        roomName = nil
        roomMetadata = nil
        logger.info("Disconnected from room")
    }

    /// Enable or disable the local camera.
    public func setCameraEnabled(_ enabled: Bool) async throws {
        #if SKIP
        guard let rm = nativeRoom else { return }
        rm.localParticipant.setCameraEnabled(enabled)
        #else
        guard let rm = nativeRoom else { return }
        try await rm.localParticipant.setCamera(enabled: enabled)
        #endif

        isCameraEnabled = enabled
        updateParticipants()
    }

    /// Enable or disable the local microphone.
    public func setMicrophoneEnabled(_ enabled: Bool) async throws {
        #if SKIP
        guard let rm = nativeRoom else { return }
        rm.localParticipant.setMicrophoneEnabled(enabled)
        #else
        guard let rm = nativeRoom else { return }
        try await rm.localParticipant.setMicrophone(enabled: enabled)
        #endif

        isMicrophoneEnabled = enabled
        updateParticipants()
    }

    /// Enable or disable screen sharing.
    public func setScreenShareEnabled(_ enabled: Bool) async throws {
        #if SKIP
        guard let rm = nativeRoom else { return }
        rm.localParticipant.setScreenShareEnabled(enabled)
        #else
        guard let rm = nativeRoom else { return }
        try await rm.localParticipant.setScreenShare(enabled: enabled)
        #endif

        isScreenShareEnabled = enabled
        updateParticipants()
    }

    /// Switch between front and back camera.
    public func switchCamera() async throws {
        #if SKIP
        guard let rm = nativeRoom else { return }
        let publication = rm.localParticipant.getTrackPublication(Track.Source.CAMERA)
        if let videoTrack = publication?.track as? LocalVideoTrack {
            videoTrack.switchCamera()
        }
        #else
        guard let rm = nativeRoom else { return }
        if let publication = rm.localParticipant.localVideoTracks.first,
           let track = publication.track as? LocalVideoTrack,
           let capturer = track.capturer as? CameraCapturer {
            try await capturer.switchCameraPosition()
        }
        #endif

        isFrontCamera = !isFrontCamera
    }

    /// Toggle between speakerphone and earpiece audio output.
    public func setSpeakerphoneEnabled(_ enabled: Bool) async {
        #if SKIP
        guard let rm = nativeRoom else { return }
        if let audioHandler = rm.audioHandler as? AudioSwitchHandler {
            let devices = audioHandler.availableAudioDevices
            for device in devices {
                if enabled && device is AudioDevice.Speakerphone {
                    audioHandler.selectDevice(device)
                } else if !enabled && device is AudioDevice.Earpiece {
                    audioHandler.selectDevice(device)
                }
            }
        }
        #elseif os(iOS)
        AudioManager.shared.isSpeakerOutputPreferred = enabled
        #endif

        isSpeakerphoneEnabled = enabled
    }

    /// Send data to other participants in the room.
    /// - Parameters:
    ///   - data: The data to send.
    ///   - reliability: Whether to use reliable (TCP-like) or lossy (UDP-like) delivery.
    ///   - topic: Optional topic string for filtering on the receiving side.
    public func publishData(_ data: Data, reliability: LiveKitDataReliability = .reliable, topic: String? = nil) async throws {
        guard let rm = nativeRoom else { return }

        #if SKIP
        let platformData = data.platformValue
        let reliabilityValue = reliability == .reliable ? DataPublishReliability.RELIABLE : DataPublishReliability.LOSSY
        rm.localParticipant.publishData(platformData, reliabilityValue, topic, nil)
        #else
        let options = DataPublishOptions(topic: topic, reliable: reliability == .reliable)
        try await rm.localParticipant.publish(data: data, options: options)
        #endif
    }

    /// Refresh the participants list from the current room state.
    public func updateParticipants() {
        guard let rm = nativeRoom else {
            participants = []
            return
        }

        var infos: [LiveKitParticipantInfo] = []

        #if SKIP
        let local = rm.localParticipant
        let localSid = "\(local.sid)"
        let localIdentity = "\(local.identity)"
        infos.append(LiveKitParticipantInfo(
            id: localSid == "null" ? "local" : localSid,
            identity: localIdentity == "null" ? "local" : localIdentity,
            name: local.name ?? "You",
            metadata: local.metadata,
            isSpeaking: local.isSpeaking,
            audioLevel: local.audioLevel,
            connectionQuality: connectionQualityFromAndroid(local.connectionQuality),
            isCameraEnabled: self.isCameraEnabled,
            isMicrophoneEnabled: self.isMicrophoneEnabled,
            isScreenShareEnabled: self.isScreenShareEnabled,
            isLocal: true
        ))
        for entry in rm.remoteParticipants {
            let p = entry.value
            let pSid = "\(p.sid)"
            let pIdentity = "\(p.identity)"
            let hasCamera = p.getTrackPublication(Track.Source.CAMERA)?.track != nil
            let hasMic = p.getTrackPublication(Track.Source.MICROPHONE)?.track != nil
            let hasScreen = p.getTrackPublication(Track.Source.SCREEN_SHARE)?.track != nil
            infos.append(LiveKitParticipantInfo(
                id: pSid == "null" ? "" : pSid,
                identity: pIdentity == "null" ? "" : pIdentity,
                name: p.name ?? (pIdentity == "null" ? "Unknown" : pIdentity),
                metadata: p.metadata,
                isSpeaking: p.isSpeaking,
                audioLevel: p.audioLevel,
                connectionQuality: connectionQualityFromAndroid(p.connectionQuality),
                isCameraEnabled: hasCamera,
                isMicrophoneEnabled: hasMic,
                isScreenShareEnabled: hasScreen,
                isLocal: false
            ))
        }
        #else
        let local = rm.localParticipant
        infos.append(LiveKitParticipantInfo(
            id: local.sid?.stringValue ?? "local",
            identity: local.identity?.stringValue ?? "local",
            name: local.name ?? "You",
            metadata: local.metadata,
            isSpeaking: local.isSpeaking,
            audioLevel: local.audioLevel,
            connectionQuality: connectionQualityFromSwift(local.connectionQuality),
            isCameraEnabled: local.isCameraEnabled(),
            isMicrophoneEnabled: local.isMicrophoneEnabled(),
            isScreenShareEnabled: local.isScreenShareEnabled(),
            isLocal: true
        ))
        for (_, participant) in rm.remoteParticipants {
            infos.append(LiveKitParticipantInfo(
                id: participant.sid?.stringValue ?? "",
                identity: participant.identity?.stringValue ?? "",
                name: participant.name ?? participant.identity?.stringValue ?? "Unknown",
                metadata: participant.metadata,
                isSpeaking: participant.isSpeaking,
                audioLevel: participant.audioLevel,
                connectionQuality: connectionQualityFromSwift(participant.connectionQuality),
                isCameraEnabled: participant.isCameraEnabled(),
                isMicrophoneEnabled: participant.isMicrophoneEnabled(),
                isScreenShareEnabled: participant.isScreenShareEnabled(),
                isLocal: false
            ))
        }
        #endif

        participants = infos
    }

    #if SKIP
    private func connectionQualityFromAndroid(_ quality: io.livekit.android.room.participant.ConnectionQuality) -> LiveKitConnectionQuality {
        if quality == io.livekit.android.room.participant.ConnectionQuality.EXCELLENT {
            return .excellent
        } else if quality == io.livekit.android.room.participant.ConnectionQuality.GOOD {
            return .good
        } else if quality == io.livekit.android.room.participant.ConnectionQuality.POOR {
            return .poor
        } else if quality == io.livekit.android.room.participant.ConnectionQuality.LOST {
            return .lost
        } else {
            return .unknown
        }
    }
    #else
    private func connectionQualityFromSwift(_ quality: ConnectionQuality) -> LiveKitConnectionQuality {
        switch quality {
        case .excellent: return .excellent
        case .good: return .good
        case .poor: return .poor
        case .lost: return .lost
        default: return .unknown
        }
    }
    #endif
}

// MARK: - Room View

/// A ready-to-use SwiftUI view that displays a LiveKit room with a participant
/// grid, local controls, and connection status.
///
/// Usage:
/// ```swift
/// LiveKitRoomView(url: "wss://your-server.livekit.cloud", token: "your-jwt-token")
/// ```
public struct LiveKitRoomView: View {
    let url: String
    let token: String

    @StateObject var manager = LiveKitRoomManager()

    public init(url: String, token: String) {
        self.url = url
        self.token = token
    }

    public var body: some View {
        VStack(spacing: 0) {
            if manager.connectionState != .connected {
                connectionStatusView
            }

            if manager.connectionState == .connected {
                participantGridView
            }

            if manager.connectionState == .connected {
                controlsBar
            }
        }
        .task {
            do {
                try await manager.connect(url: url, token: token)
            } catch {
                logger.error("Room connection failed: \(error.localizedDescription)")
            }
        }
    }

    var connectionStatusView: some View {
        VStack(spacing: 16) {
            Spacer()
            if manager.connectionState == .connecting || manager.connectionState == .reconnecting {
                ProgressView()
                Text(manager.connectionState == .connecting ? "Connecting..." : "Reconnecting...")
                    .foregroundStyle(.secondary)
            } else if let error = manager.errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("Disconnected")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    var participantGridView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(manager.participants) { participant in
                    participantTile(participant)
                }
            }
            .padding(8)
        }
    }

    var gridColumns: [GridItem] {
        let count = manager.participants.count
        let columns = count <= 1 ? 1 : (count <= 4 ? 2 : 3)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)
    }

    func participantTile(_ participant: LiveKitParticipantInfo) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.15))
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if !participant.isCameraEnabled {
                        VStack(spacing: 8) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.white.opacity(0.4))
                            Text(participant.name)
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        if participant.isScreenShareEnabled {
                            Image(systemName: "rectangle.on.rectangle")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        connectionQualityIcon(participant.connectionQuality)
                    }
                    .padding(8)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 4) {
                        if participant.isSpeaking {
                            Image(systemName: "waveform")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        Text(participant.isLocal ? "You" : participant.name)
                            .font(.caption2)
                            .foregroundStyle(.white)
                        if !participant.isMicrophoneEnabled {
                            Image(systemName: "mic.slash.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(8)
                }

            if participant.isSpeaking {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.green, lineWidth: 2)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
    }

    func connectionQualityIcon(_ quality: LiveKitConnectionQuality) -> some View {
        let icon: String
        let color: Color
        switch quality {
        case .excellent:
            icon = "wifi"
            color = .green
        case .good:
            icon = "wifi"
            color = .white
        case .poor:
            icon = "wifi.exclamationmark"
            color = .yellow
        case .lost:
            icon = "wifi.slash"
            color = .red
        case .unknown:
            icon = "wifi"
            color = Color.white.opacity(0.3)
        }
        return Image(systemName: icon)
            .font(.caption2)
            .foregroundStyle(color)
    }

    var controlsBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                controlButton(
                    icon: manager.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill",
                    isActive: manager.isMicrophoneEnabled,
                    activeColor: .white,
                    inactiveColor: .red
                ) {
                    Task { try? await manager.setMicrophoneEnabled(!manager.isMicrophoneEnabled) }
                }

                controlButton(
                    icon: manager.isCameraEnabled ? "video.fill" : "video.slash.fill",
                    isActive: manager.isCameraEnabled,
                    activeColor: .white,
                    inactiveColor: .red
                ) {
                    Task { try? await manager.setCameraEnabled(!manager.isCameraEnabled) }
                }

                if manager.isCameraEnabled {
                    controlButton(
                        icon: "camera.rotate.fill",
                        isActive: true,
                        activeColor: .white,
                        inactiveColor: .white
                    ) {
                        Task { try? await manager.switchCamera() }
                    }
                }

                controlButton(
                    icon: manager.isScreenShareEnabled ? "rectangle.inset.filled.and.person.filled" : "rectangle.on.rectangle",
                    isActive: manager.isScreenShareEnabled,
                    activeColor: .green,
                    inactiveColor: .white
                ) {
                    Task { try? await manager.setScreenShareEnabled(!manager.isScreenShareEnabled) }
                }

                controlButton(
                    icon: manager.isSpeakerphoneEnabled ? "speaker.wave.2.fill" : "speaker.fill",
                    isActive: manager.isSpeakerphoneEnabled,
                    activeColor: .white,
                    inactiveColor: .white
                ) {
                    Task { try? await manager.setSpeakerphoneEnabled(!manager.isSpeakerphoneEnabled) }
                }

                Button(action: {
                    Task { await manager.disconnect() }
                }) {
                    Image(systemName: "phone.down.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.1))
    }

    func controlButton(icon: String, isActive: Bool, activeColor: Color, inactiveColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isActive ? activeColor : inactiveColor)
                .frame(width: 50, height: 50)
                .background(Color(white: 0.2))
                .clipShape(Circle())
        }
    }
}

// MARK: - Connection View

/// A simple view for entering LiveKit server URL and token.
/// Useful for development and testing.
///
/// Usage:
/// ```swift
/// LiveKitConnectView { url, token in
///     LiveKitRoomView(url: url, token: token)
/// }
/// ```
public struct LiveKitConnectView<Content: View>: View {
    @State var url: String = ""
    @State var token: String = ""
    @State var isConnected: Bool = false

    let content: (String, String) -> Content

    public init(@ViewBuilder content: @escaping (String, String) -> Content) {
        self.content = content
    }

    public var body: some View {
        if isConnected {
            content(url, token)
        } else {
            Form {
                Section("LiveKit Server") {
                    TextField("Server URL", text: $url)
                        #if !SKIP
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        #endif
                    TextField("Access Token", text: $token)
                        #if !SKIP
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        #endif
                }

                Section {
                    Button("Connect") {
                        if !url.isEmpty && !token.isEmpty {
                            isConnected = true
                        }
                    }
                    .disabled(url.isEmpty || token.isEmpty)
                }
            }
            .navigationTitle("Connect to Room")
        }
    }
}
