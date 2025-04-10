// ABOUTME: Menu bar app for StageWhisper dictation
// ABOUTME: Provides a status item and hotkey management

import Foundation
import AppKit
import ApplicationServices
import HotKey
import AVFoundation
import ObjectiveC

// Menu bar app delegate
class DictationAppDelegate: NSObject, NSApplicationDelegate, TranscriptionDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var recorder: AudioRecorder?
    private var isRecording = false
    private var whisperTranscriber: WhisperTranscriber?
    private var currentTranscription: String = ""
    private var isStreamingMode = true  // Default to streaming mode
    
    // Prevent deallocation while app is running
    private var retainSelf: DictationAppDelegate?
    
    // UI elements
    let micIcon = "🎤"
    let recordingIcon = "🔴"
    let downloadingIcon = "⬇️"
    let loadingIcon = "⏳"
    let readyIcon = "✅"
    let errorIcon = "❌"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Starting dictation mode with hotkey \(Config.hotkeyModifiers.description)+\(Config.hotkeyKey.description)")
        
        // Retain self to prevent deallocation
        retainSelf = self
        
        do {
            // Initialize everything - order matters!
            // First create the menu bar item
            setupMenuBar()
            // Then initialize other components
            setupRecorder()
            registerHotkey()
            // Initialize WhisperKit last (will update the menu)
            setupWhisper()
        } catch {
            print("ERROR: Failed to initialize application: \(error)")
        }
    }
    
    private func setupWhisper() {
        // Initialize WhisperKit transcriber
        whisperTranscriber = WhisperTranscriber.createDefault()
        
        // Set the transcription delegate to self
        whisperTranscriber?.delegate = self
        
        guard let statusItem = statusItem else {
            print("ERROR: Status item not initialized")
            return
        }
        
        // Show loading in menu bar
        if let button = statusItem.button {
            button.title = loadingIcon
            button.toolTip = "Initializing WhisperKit model..."
        }
        
        // Pre-load model in background
        Task {
            // Register for download progress updates
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("WhisperKitDownloadProgress"),
                object: nil,
                queue: .main) { [weak self] notification in
                    if let progress = notification.userInfo?["progress"] as? Double,
                       let status = notification.userInfo?["status"] as? String,
                       let self = self,
                       let statusItem = self.statusItem,
                       let button = statusItem.button {
                        // Update menu bar with download progress
                        let progressPercent = Int(progress * 100)
                        button.title = "\(self.downloadingIcon) \(progressPercent)%"
                        button.toolTip = status
                    }
                }
            
            // Show loading state
            print("Loading WhisperKit model...")
            print("This may take some time as the model will be downloaded automatically...")
            
            guard let whisperTranscriber = whisperTranscriber else {
                print("ERROR: Transcriber not initialized")
                return
            }
            
            // Let WhisperKit handle the auto-download
            let modelLoaded = await whisperTranscriber.loadModel()
            
            // Update UI based on result
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard let statusItem = self.statusItem else { return }
                
                if modelLoaded {
                    print("WhisperKit model initialized successfully!")
                    if let button = statusItem.button {
                        button.title = self.readyIcon
                        button.toolTip = "WhisperKit ready - Press ⌘⇧Z to dictate"
                        
                        // Animate back to normal icon after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                            guard let self = self, let statusItem = self.statusItem else { return }
                            if let button = statusItem.button {
                                button.title = self.micIcon
                                button.toolTip = "StageWhisper - Press ⌘⇧Z to dictate"
                            }
                        }
                    }
                } else {
                    print("\nModel initialization failed. The app needs actual model files to work.")
                    print("\nThe application attempted to download the model files but failed.")
                    print("You may want to try again with a better internet connection or")
                    print("check if the model server is accessible.")
                    
                    if let button = statusItem.button {
                        button.title = self.errorIcon
                        button.toolTip = "WhisperKit initialization failed - Model files are missing"
                    }
                }
            }
        }
    }
    
    // MARK: - TranscriptionDelegate methods
    
    func transcriptionDidUpdate(text: String, isFinal: Bool) {
        // Update current transcription
        currentTranscription = text
        
        // Update UI to show we have some text
        if let statusItem = statusItem, let button = statusItem.button {
            // Keep the recording icon, but add a text indicator
            button.title = "\(recordingIcon) ..."
            button.toolTip = "Transcribing: \(text.prefix(30))..."
        }
        
        // Print the current transcription in verbose mode
        if Config.verbose {
            print("Transcription updated: \"\(text)\"")
        }
        
        // If it's the final result and we're still recording, 
        // we don't need to do anything special here as the
        // key-up handler will take care of inserting the text
    }
    
    func transcriptionDidError(error: Error) {
        print("ERROR: Transcription error: \(error)")
        
        // Update UI to show error
        if let statusItem = statusItem, let button = statusItem.button {
            button.title = errorIcon
            button.toolTip = "Transcription error: \(error.localizedDescription)"
            
            // Restore normal icon after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self, let statusItem = self.statusItem else { return }
                if let button = statusItem.button {
                    button.title = self.micIcon
                    button.toolTip = "StageWhisper - Press ⌘⇧Z to dictate"
                }
            }
        }
    }
    
    private func setupMenuBar() {
        // Create the status item in the menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let statusItem = statusItem else {
            print("ERROR: Failed to create status item")
            return
        }
        
        if let button = statusItem.button {
            button.title = micIcon
            button.toolTip = "StageWhisper - Press ⌘⇧Z to dictate"
        }
        
        // Setup menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Dictate (⌘⇧Z)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    private func setupRecorder() {
        recorder = AudioRecorder()
    }
    
    private func registerHotkey() {
        hotKey = HotKey(key: Config.hotkeyKey, modifiers: Config.hotkeyModifiers)
        
        guard let hotKey = hotKey else {
            print("ERROR: Failed to create hotkey")
            return
        }
        
        // Key down handler - start recording
        hotKey.keyDownHandler = { [weak self] in
            guard let self = self, !self.isRecording else { return }
            
            print("Recording started...")
            if let statusItem = self.statusItem, let button = statusItem.button {
                button.title = self.recordingIcon
            }
            
            guard let recorder = self.recorder else {
                print("ERROR: Recorder not initialized")
                return
            }
            
            guard let transcriber = self.whisperTranscriber else {
                print("ERROR: Transcriber not initialized")
                return
            }
            
            // Reset current transcription
            self.currentTranscription = ""
            
            // Start recording in streaming or normal mode based on setting
            if isStreamingMode {
                // Start recording with streaming transcription
                recorder.startStreamingRecording(with: transcriber)
            } else {
                // Start recording in normal mode
                recorder.startRecording()
            }
            
            self.isRecording = true
        }
        
        // Key up handler - stop recording and process transcription
        hotKey.keyUpHandler = { [weak self] in
            guard let self = self else {
                print("ERROR: Self is nil in keyUpHandler")
                return
            }
            
            guard self.isRecording else {
                print("WARNING: Key up received but not recording - ignoring")
                return
            }
            
            print("Recording stopped. Finalizing transcription...")
            
            // Update UI back to normal
            if let statusItem = self.statusItem, let button = statusItem.button {
                button.title = self.micIcon
            }
            
            self.isRecording = false
            
            // Check recorder is valid
            guard let recorder = self.recorder else {
                print("ERROR: Audio recorder is nil")
                return
            }
            
            if isStreamingMode {
                // In streaming mode, we already have the transcription
                let transcription = self.currentTranscription
                
                // Stop the streaming transcription
                recorder.stopRecording()
                
                // Insert the transcribed text
                if !transcription.isEmpty {
                    print("Transcription complete: \"\(transcription)\"")
                    
                    // Insert text at cursor on main thread
                    DispatchQueue.main.async {
                        print("Inserting text at cursor...")
                        let success = insertTextAtCursor(transcription)
                        
                        if !success {
                            print("Failed to insert text, trying alternative method...")
                            _ = typeTextDirectly(transcription)
                        }
                    }
                } else {
                    print("WARNING: Empty transcription result - nothing to insert")
                }
            } else {
                // In file mode, we need to transcribe the audio file
                if let audioURL = recorder.stopRecording() {
                    // Process transcription asynchronously
                    Task {
                        print("Processing audio file: \(audioURL.lastPathComponent)")
                        
                        // Check transcriber is valid
                        guard let transcriber = self.whisperTranscriber else {
                            print("ERROR: WhisperTranscriber is nil")
                            return
                        }
                        
                        // Transcribe audio
                        print("Starting transcription...")
                        if let transcription = await transcriber.transcribeAudioFile(at: audioURL) {
                            print("Transcription complete: \"\(transcription)\"")
                            
                            // If empty transcription, don't try to insert
                            guard !transcription.isEmpty else {
                                print("WARNING: Empty transcription result - nothing to insert")
                                return
                            }
                            
                            // Insert text at cursor on main thread
                            DispatchQueue.main.async {
                                print("Inserting text at cursor...")
                                let success = insertTextAtCursor(transcription)
                                
                                if !success {
                                    print("Failed to insert text, trying alternative method...")
                                    _ = typeTextDirectly(transcription)
                                }
                            }
                        } else {
                            print("ERROR: Transcription failed or returned nil")
                        }
                    }
                } else {
                    print("ERROR: No audio captured - recorder.stopRecording() returned nil")
                }
            }
        }
        
        print("Ready to record. Press \(Config.hotkeyModifiers.description)+\(Config.hotkeyKey.description) to dictate.")
    }
}

// Start the menu bar app
func startDictationApp() {
    // Check accessibility permissions first
    let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
    let options = [checkOptPrompt: true] as CFDictionary
    let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
    
    if !accessibilityEnabled {
        print("ERROR: Accessibility permissions required")
        print("Please grant StageWhisper app Accessibility permissions in:")
        print("System Settings > Privacy & Security > Accessibility")
        exit(1)
    }
    
    // Check microphone permissions
    let micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
    if micPermission != .authorized {
        print("Requesting microphone permissions...")
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted {
                DispatchQueue.main.async {
                    startDictationAppUI()
                }
            } else {
                print("ERROR: Microphone permission denied")
                print("Please grant StageWhisper app Microphone permissions in:")
                print("System Settings > Privacy & Security > Microphone")
                exit(1)
            }
        }
    } else {
        startDictationAppUI()
    }
}

// Start the UI part of the app
func startDictationAppUI() {
    // Create the delegate
    let dictationDelegate = DictationAppDelegate()
    
    // Store a reference to the dictation delegate
    objc_setAssociatedObject(NSApp, "dictationDelegate", dictationDelegate, .OBJC_ASSOCIATION_RETAIN)
    
    // Since we're already running within the NSApplication context,
    // we just need to register our dictation delegate to handle the UI
    NSApp.activate(ignoringOtherApps: true)
    
    // Initialize the delegate
    dictationDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    
    print("Menu bar app started - look for the 🎤 icon in your menu bar")
}