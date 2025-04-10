# StageWhisper

A macOS command-line tool that inserts text at the current cursor position, with voice dictation support using WhisperKit.

## Features

- Insert text at current cursor position in any application
- Voice dictation via menu bar app with global hotkey (Command+Shift+Z)
- Uses WhisperKit for high-quality speech recognition
- Preserves clipboard contents when inserting text

## Requirements

- macOS 13.0 or later
- Terminal with Accessibility permissions
- Microphone access for dictation

## Installation

### 1. Build the Tool

```bash
# Clone the repository
git clone https://github.com/yourusername/StageWhisper.git
cd StageWhisper

# Build swift-insert
swift build -c release

# Optional: Copy to your PATH
cp .build/release/swift-insert /usr/local/bin/
```

WhisperKit models will be automatically downloaded on first use.

## Usage

### Text Insertion

```bash
# Insert text at the current cursor position
swift-insert "Hello, world!"
```

### Voice Dictation

```bash
# Start dictation mode (menu bar app)
swift-insert --dictate
```

Once dictation mode is running:
1. A microphone icon (🎤) will appear in your menu bar
2. Press and hold Command+Shift+Z to start recording
3. The icon will change to 🔴 while recording
4. Speak your text
5. Release the hotkey
6. The transcribed text will be inserted at your cursor position

To quit, click the menu bar icon and select "Quit".

## Permissions

The tool requires:
- Accessibility permissions (for text insertion)
- Microphone permissions (for dictation)

You'll be prompted to grant these when needed.

## Dictation Settings

By default, the app uses the "tiny" Whisper model. For better accuracy, you can modify `WhisperTranscriber.swift` to use a larger model:

```swift
// Available models: .tiny, .base, .small, .medium, .large-v3
let modelVariant: WhisperKitModelVariant = .tiny
```

Larger models provide better transcription accuracy but require more memory and processing power.

## How It Works

1. **Text Insertion:** Uses macOS Accessibility APIs to insert text at the current cursor position
2. **Voice Dictation:** 
   - Records audio while the hotkey is pressed
   - Processes the audio using WhisperKit (Whisper implementation for Apple platforms)
   - Inserts the transcribed text at the cursor position
3. **WhisperKit Integration:**
   - Automatically downloads the appropriate model on first use
   - Provides fast, on-device speech recognition
   - No audio data is sent to external servers

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - Swift implementation of Whisper for Apple platforms
- [HotKey](https://github.com/soffes/HotKey) - Simple global keyboard shortcuts for macOS

## License

MIT