import WebRTC

// MARK: - WebRTCManager
class WebRTCManager: NSObject, ObservableObject {
    // UI State
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var eventTypeStr: String = ""
    
    // Basic conversation text
    @Published var conversation: [ConversationItem] = []
    @Published var outgoingMessage: String = ""
    
    // We’ll store items by item_id for easy updates
    private var conversationMap: [String : ConversationItem] = [:]
    
    // Model & session config
    private var modelName: String = "gpt-4o-mini-realtime-preview-2024-12-17"
    private var systemInstructions: String = ""
    private var voice: String = "alloy"
    
    // WebRTC references
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var audioTrack: RTCAudioTrack?
    
    // MARK: - Public Methods
    
    /// Start a WebRTC connection using a standard API key for local testing.
    func startConnection(
        apiKey: String,
        modelName: String,
        systemMessage: String,
        voice: String
    ) {
        conversation.removeAll()
        conversationMap.removeAll()
        
        // Store updated config
        self.modelName = modelName
        self.systemInstructions = systemMessage
        self.voice = voice
        
        setupPeerConnection()
        setupLocalAudio()
        configureAudioSession()
        
        guard let peerConnection = peerConnection else { return }
        
        // Create a Data Channel for sending/receiving events
        let config = RTCDataChannelConfiguration()
        if let channel = peerConnection.dataChannel(forLabel: "oai-events", configuration: config) {
            dataChannel = channel
            dataChannel?.delegate = self
        }
        
        // Create an SDP offer
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["levelControl": "true"],
            optionalConstraints: nil
        )
        peerConnection.offer(for: constraints) { [weak self] sdp, error in
            guard let self = self,
                  let sdp = sdp,
                  error == nil else {
                print("Failed to create offer: \(String(describing: error))")
                return
            }
            // Set local description
            peerConnection.setLocalDescription(sdp) { [weak self] error in
                guard let self = self, error == nil else {
                    print("Failed to set local description: \(String(describing: error))")
                    return
                }
                
                Task {
                    do {
                        guard let localSdp = peerConnection.localDescription?.sdp else {
                            return
                        }
                        // Post SDP offer to Realtime
                        let answerSdp = try await self.fetchRemoteSDP(apiKey: apiKey, localSdp: localSdp)
                        
                        // Set remote description (answer)
                        let answer = RTCSessionDescription(type: .answer, sdp: answerSdp)
                        peerConnection.setRemoteDescription(answer) { error in
                            DispatchQueue.main.async {
                                if let error {
                                    print("Failed to set remote description: \(error)")
                                    self.connectionStatus = .disconnected
                                } else {
                                    self.connectionStatus = .connected
                                }
                            }
                        }
                    } catch {
                        print("Error fetching remote SDP: \(error)")
                        self.connectionStatus = .disconnected
                    }
                }
            }
        }
    }
    
    func stopConnection() {
        peerConnection?.close()
        peerConnection = nil
        dataChannel = nil
        audioTrack = nil
        connectionStatus = .disconnected
    }
    
    /// Sends a custom "conversation.item.create" event
    func sendMessage() {
        guard let dc = dataChannel,
              !outgoingMessage.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        
        let realtimeEvent: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": outgoingMessage
                    ]
                ]
            ]
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: realtimeEvent) {
            let buffer = RTCDataBuffer(data: jsonData, isBinary: false)
            dc.sendData(buffer)
            self.outgoingMessage = ""
            createResponse()
        }
    }
    
    /// Sends a "response.create" event
    func createResponse() {
        guard let dc = dataChannel else { return }
        
        let realtimeEvent: [String: Any] = [ "type": "response.create" ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: realtimeEvent) {
            let buffer = RTCDataBuffer(data: jsonData, isBinary: false)
            dc.sendData(buffer)
        }
    }
    
    /// Called automatically when data channel opens, or you can manually call it.
    /// Updates session configuration with the latest instructions and voice.
    func sendSessionUpdate() {
        guard let dc = dataChannel, dc.readyState == .open else {
            print("Data channel is not open. Cannot send session.update.")
            return
        }
        
        let sessionUpdate: [String: Any] = [
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],  // Enable both text and audio
                "instructions": systemInstructions,
                "voice": voice,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": "whisper-1"
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 500,
                    "create_response": true
                ],
                "max_response_output_tokens": "inf"
            ]
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: sessionUpdate)
            let buffer = RTCDataBuffer(data: jsonData, isBinary: false)
            dc.sendData(buffer)
            print("session.update event sent.")
        } catch {
            print("Failed to serialize session.update JSON: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func setupPeerConnection() {
        let config = RTCConfiguration()
        // If needed, configure ICE servers here
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let factory = RTCPeerConnectionFactory()
        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)
    }
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setMode(.videoChat)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
    }
    
    private func setupLocalAudio() {
        guard let peerConnection = peerConnection else { return }
        let factory = RTCPeerConnectionFactory()
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "googEchoCancellation": "true",
                "googAutoGainControl": "true",
                "googNoiseSuppression": "true",
                "googHighpassFilter": "true"
            ],
            optionalConstraints: nil
        )
        
        let audioSource = factory.audioSource(with: constraints)
        
        let localAudioTrack = factory.audioTrack(with: audioSource, trackId: "local_audio")
        peerConnection.add(localAudioTrack, streamIds: ["local_stream"])
        audioTrack = localAudioTrack
    }
    
    /// Posts our SDP offer to the Realtime API, returns the answer SDP.
    private func fetchRemoteSDP(apiKey: String, localSdp: String) async throws -> String {
        let baseUrl = "https://api.openai.com/v1/realtime"
        guard let url = URL(string: "\(baseUrl)?model=\(modelName)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = localSdp.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "WebRTCManager.fetchRemoteSDP",
                          code: code,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        
        guard let answerSdp = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "WebRTCManager.fetchRemoteSDP",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to decode SDP"])
        }
        
        return answerSdp
    }
    
    private func handleIncomingJSON(_ jsonString: String) {
        print("Received JSON:\n\(jsonString)\n")
        
        guard let data = jsonString.data(using: .utf8),
              let rawEvent = try? JSONSerialization.jsonObject(with: data),
              let eventDict = rawEvent as? [String: Any],
              let eventType = eventDict["type"] as? String else {
            return
        }
        
        eventTypeStr = eventType
        
        switch eventType {
        case "conversation.item.created":
            if let item = eventDict["item"] as? [String: Any],
               let itemId = item["id"] as? String,
               let role = item["role"] as? String
            {
                // If item contains "content", extract the text
                let text = (item["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
                
                let newItem = ConversationItem(id: itemId, role: role, text: text)
                conversationMap[itemId] = newItem
                if role == "assistant" || role == "user" {
                    conversation.append(newItem)
                }
            }
            
        case "response.audio_transcript.delta":
            // partial transcript for assistant’s message
            if let itemId = eventDict["item_id"] as? String,
               let delta = eventDict["delta"] as? String
            {
                if var convItem = conversationMap[itemId] {
                    convItem.text += delta
                    conversationMap[itemId] = convItem
                    if let idx = conversation.firstIndex(where: { $0.id == itemId }) {
                        conversation[idx].text = convItem.text
                    }
                }
            }
            
        case "response.audio_transcript.done":
            // final transcript for assistant’s message
            if let itemId = eventDict["item_id"] as? String,
               let transcript = eventDict["transcript"] as? String
            {
                if var convItem = conversationMap[itemId] {
                    convItem.text = transcript
                    conversationMap[itemId] = convItem
                    if let idx = conversation.firstIndex(where: { $0.id == itemId }) {
                        conversation[idx].text = transcript
                    }
                }
            }
            
        case "conversation.item.input_audio_transcription.completed":
            // final transcript for user's audio input
            if let itemId = eventDict["item_id"] as? String,
               let transcript = eventDict["transcript"] as? String
            {
                if var convItem = conversationMap[itemId] {
                    convItem.text = transcript
                    conversationMap[itemId] = convItem
                    if let idx = conversation.firstIndex(where: { $0.id == itemId }) {
                        conversation[idx].text = transcript
                    }
                }
            }
            
        default:
            break
        }
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("ICE Connection State changed to: \(newState)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        // If the server creates the data channel on its side, handle it here
        dataChannel.delegate = self
    }
}

// MARK: - RTCDataChannelDelegate
extension WebRTCManager: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("Data channel state changed: \(dataChannel.readyState)")
        // Auto-send session.update after channel is open
        if dataChannel.readyState == .open {
            sendSessionUpdate()
        }
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel,
                     didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let message = String(data: buffer.data, encoding: .utf8) else {
            return
        }
        DispatchQueue.main.async {
            self.handleIncomingJSON(message)
        }
    }
}
