# Installation Guide for swift-insert with Whisper Dictation

This guide will walk you through the complete installation process for `swift-insert` with the native MLX Swift whisper dictation capability.

## Prerequisites

- macOS 13.3 or later
- Xcode command line tools: `xcode-select --install`
- Swift 5.8 or later

## Step 1: Clone the Repository

```bash
git clone https://github.com/yourusername/swift-insert.git
cd swift-insert
```

## Step 2: Download the Whisper Model

Download the Whisper model from Hugging Face:

```bash
# Create a directory for the model
mkdir -p ~/whisper-models/large-v3-turbo

# Method 1: Using huggingface_hub (if you have Python installed)
pip3 install huggingface_hub
python3 -c "import huggingface_hub; huggingface_hub.snapshot_download('mlx-community/whisper-large-v3-turbo', local_dir='~/whisper-models/large-v3-turbo')"

# Method 2: Manual download
# Visit https://huggingface.co/mlx-community/whisper-large-v3-turbo
# Download the model files to ~/whisper-models/large-v3-turbo
```

## Step 4: Build swift-insert

Build the application:

```bash
swift build -c release
```

## Step 5: Install to Your PATH (Optional)

For convenience, you can install the tool system-wide:

```bash
sudo cp .build/release/swift-insert /usr/local/bin/
```

## Step 6: Grant Permissions

### Accessibility Permissions

1. Open **System Settings** > **Privacy & Security** > **Accessibility**
2. Click the "+" button
3. Add your Terminal application (Terminal, iTerm2, etc.)
4. Check the box next to it to enable accessibility control

### Microphone Permissions

1. Open **System Settings** > **Privacy & Security** > **Microphone**
2. Find your Terminal application in the list
3. Enable the toggle to allow microphone access

## Step 7: Test the Installation

Test the text insertion:

```bash
swift-insert "Hello, world!"
```

Test the dictation mode:

```bash
swift-insert --dictate
```

When dictation mode starts:
1. The app will appear as a small waveform icon in your menu bar
2. Press and hold Command+Shift+Z to start dictation
3. The icon will change to indicate recording is in progress
4. Speak your text
5. Release the key to stop recording and process your speech
6. The transcribed text will be inserted at your cursor position

To quit dictation mode, click on the menu bar icon and select "Quit" from the menu.

## Troubleshooting

### No Audio Input Detected

- Check that your microphone is working by testing it in another application
- Verify that Terminal has microphone permissions
- Run with verbose logging: `swift-insert --dictate --verbose`

### Transcription Errors

- Make sure you've downloaded the correct model
- Check the Python script output for any errors
- Try speaking clearly and in a quiet environment

### Permission Issues

If you see errors about not being able to get the focused application:
- Make sure you've granted Accessibility permissions
- Try restarting your Terminal
- Log out and back into your macOS account

### Python Issues

If the Python bridge fails:
- Verify Python 3 is installed: `python3 --version`
- Check MLX is installed: `pip3 list | grep mlx`
- Ensure the model is downloaded correctly