// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import Foundation
import SwiftUI
import OSLog
#if SKIP
import io.livekit.android.__
import io.livekit.android.room.__
import io.livekit.android.room.participant.__
import io.livekit.android.room.track.__
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

// MARK: - Participant Info

/// Platform-independent representation of a room participant.
public struct LiveKitParticipantInfo: Identifiable {
    public let id: String
    public let identity: String
    public let name: String
    public let isSpeaking: Bool
    public let isCameraEnabled: Bool
    public let isMicrophoneEnabled: Bool
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
    @Published public var roomName: String?

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
        roomName = nil
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
            isSpeaking: false,
            isCameraEnabled: self.isCameraEnabled,
            isMicrophoneEnabled: self.isMicrophoneEnabled,
            isLocal: true
        ))
        for entry in rm.remoteParticipants {
            let p = entry.value
            let pSid = "\(p.sid)"
            let pIdentity = "\(p.identity)"
            infos.append(LiveKitParticipantInfo(
                id: pSid == "null" ? "" : pSid,
                identity: pIdentity == "null" ? "" : pIdentity,
                name: p.name ?? (pIdentity == "null" ? "Unknown" : pIdentity),
                isSpeaking: false,
                isCameraEnabled: false,
                isMicrophoneEnabled: false,
                isLocal: false
            ))
        }
        #else
        let local = rm.localParticipant
        infos.append(LiveKitParticipantInfo(
            id: local.sid?.stringValue ?? "local",
            identity: local.identity?.stringValue ?? "local",
            name: local.name ?? "You",
            isSpeaking: local.isSpeaking,
            isCameraEnabled: local.isCameraEnabled(),
            isMicrophoneEnabled: local.isMicrophoneEnabled(),
            isLocal: true
        ))
        for (_, participant) in rm.remoteParticipants {
            infos.append(LiveKitParticipantInfo(
                id: participant.sid?.stringValue ?? "",
                identity: participant.identity?.stringValue ?? "",
                name: participant.name ?? participant.identity?.stringValue ?? "Unknown",
                isSpeaking: participant.isSpeaking,
                isCameraEnabled: participant.isCameraEnabled(),
                isMicrophoneEnabled: participant.isMicrophoneEnabled(),
                isLocal: false
            ))
        }
        #endif

        participants = infos
    }
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
        ZStack(alignment: .bottomLeading) {
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
    }

    var controlsBar: some View {
        HStack(spacing: 24) {
            Button(action: {
                Task { try? await manager.setMicrophoneEnabled(!manager.isMicrophoneEnabled) }
            }) {
                Image(systemName: manager.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill")
                    .font(.title2)
                    .foregroundStyle(manager.isMicrophoneEnabled ? .white : .red)
                    .frame(width: 50, height: 50)
                    .background(Color(white: 0.2))
                    .clipShape(Circle())
            }

            Button(action: {
                Task { try? await manager.setCameraEnabled(!manager.isCameraEnabled) }
            }) {
                Image(systemName: manager.isCameraEnabled ? "video.fill" : "video.slash.fill")
                    .font(.title2)
                    .foregroundStyle(manager.isCameraEnabled ? .white : .red)
                    .frame(width: 50, height: 50)
                    .background(Color(white: 0.2))
                    .clipShape(Circle())
            }

            Button(action: {
                Task { await manager.disconnect() }
            }) {
                Image(systemName: "phone.down.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.red)
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.1))
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
