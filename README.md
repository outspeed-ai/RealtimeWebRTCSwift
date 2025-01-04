# OpenAI Swift Realtime API with WebRTC
![Swift](https://img.shields.io/badge/Swift-5-orange?logo=swift)
![iOS](https://img.shields.io/badge/iOS-16%2B-blue?logo=apple)

### Overview

This Xcode project demos OpenAI's [**Realtime API with WebRTC**](https://platform.openai.com/docs/guides/realtime-webrtc) (Advanced Voice Mode). It's an iOS application built with SwiftUI, AVFoundation, and the [WebRTC](https://github.com/stasel/WebRTC) package. It supports full AVM capabilities including interrupting the audio, sending text events manually, and controlling options such as the system message, realtime audio model, and voice.

https://github.com/user-attachments/assets/0e731764-569a-4f35-976e-972ef16cb699

> This video demos the iOS application running on MacOS

---

## Requirements
- iOS 16.0 or later
- OpenAI API Key

---

## Installation

1. **Clone the the Repository**:
   ```bash
   git clone https://github.com/PallavAg/VoiceModeWebRTCSwift.git
   ```

3. **Setup API Key**:
   - Replace the placeholder `API_KEY` in the code with your OpenAI API key:
     ```swift
     let API_KEY = "your_openai_api_key"
     ```
   - Alternatively, you can specify the OpenAI API Key in the app itself

3. **Run the App**:
   - Go to the **Signing & Capabilities** section to first specify your account.
   - Build and run the app on your iOS device, MacOS device, or simulator.

---

## Usage

1. **Start Connection**:
   - Launch the app and enter your API key in **Settings** if not specified already.
   - Select your preferred AI model and voice, then press 'Start Connection' to begin the conversation.

2. **Interact**:
   - Use the text input field or speak into the microphone to interact with the Realtime API.

---

## Key Components

- **`ContentView`**:
  - The primary UI that orchestrates conversation, input, and connection controls.
- **`WebRTCManager`**:
  - Handles WebRTC connection setup, data channel communication, and audio processing.
- **`OptionsView`**:
  - Allows customization of API keys, models, and voice settings.

---

## Troubleshooting

- **Microphone Permission**:
  - Ensure the app has microphone access in iOS settings.
- **Connection Issues**:
  - Check API key validity and server accessibility.

---

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
