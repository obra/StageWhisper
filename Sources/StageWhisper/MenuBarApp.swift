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
    // Track previous transcription to detect changes
    private var previousTranscription: String = ""
    
    // Prevent deallocation while app is running
    private var retainSelf: DictationAppDelegate?
    
    // UI elements
    let micIcon = "🎤"
    let recordingIcon = "🔴"
    let downloadingIcon = "⬇️"
    let loadingIcon = "⏳"
    let processingIcon = "⚙️"
    let readyIcon = "✅"
    let errorIcon = "❌"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Starting dictation mode with hotkey \(Config.hotkeyModifiers.description)+\(Config.hotkeyKey.description)")
        
        // Retain self to prevent deallocation
        retainSelf = self
        
        // Initialize everything - order matters!
        // First create the menu bar item
        setupMenuBar()
        // Then initialize other components
        setupRecorder()
        registerHotkey()
        // Initialize WhisperKit last (will update the menu)
        setupWhisper()
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
        // Print transcription updates for debugging
        if isFinal {
            Swift.print("FINAL TRANSCRIPTION: \"\(text)\"")
        } else {
            Swift.print("Intermediate transcription: \"\(text)\"")
        }
        
        // CRITICAL: This is where real-time insertion happens
        // The issue is we're now explicitly inserting text AS it's recognized
        
        // Don't try to insert empty text
        if !text.isEmpty {
            if isRecording || isFinal {
                // We have text and we're recording or finalizing - determine what to insert
                let oldText = previousTranscription  // Use previousTranscription, not currentTranscription
                
                // Calculate what's new in this transcription compared to previous one
                if oldText.isEmpty {
                    // First transcription - insert everything
                    Swift.print("REAL-TIME: First transcription chunk - inserting all: \"\(text)\"")
                    self.insertPartialTranscription(text)
                } else if text != oldText {
                    // Only insert what's new
                    let newText = self.getNewTextToInsert(oldText: oldText, newText: text)
                    if !newText.isEmpty {
                        Swift.print("REAL-TIME: Inserting new text: \"\(newText)\"")
                        self.insertPartialTranscription(newText)
                    }
                }
            }
        }
        
        // Store the new transcription AFTER processing
        previousTranscription = text
        currentTranscription = text
        
        // Update UI with the current partial transcription for immediate feedback
        if let statusItem = statusItem, let button = statusItem.button {
            // Show first few characters of partial transcription
            let previewText = text.prefix(15).trimmingCharacters(in: .whitespacesAndNewlines)
            if !previewText.isEmpty {
                button.title = "\(recordingIcon) \(previewText)..."
            } else {
                button.title = "\(recordingIcon) ..."
            }
            button.toolTip = "Transcribing: \(text.prefix(30))..."
        }
        
        // Handle final transcription when not recording
        if !isRecording && isFinal {
            // This is the final result after stopping
            Swift.print("Transcription complete. Final text will be inserted by keyUpHandler")
            
            // Update UI to indicate processing is complete but insertion is pending
            if let statusItem = statusItem, let button = statusItem.button {
                button.title = processingIcon
                button.toolTip = "Processing complete. Inserting text..."
            }
            
            // IMPORTANT: Do NOT insert text here - only keyUpHandler should do that
        }
    }
    
    func transcriptionDidError(error: Error) {
        Swift.print("ERROR: Transcription error: \(error)")
        
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
    
    /// Helper method to determine what new text to insert
    private func getNewTextToInsert(oldText: String, newText: String) -> String {
        // Method 1: If new text is longer and contains old text at the beginning
        if newText.hasPrefix(oldText) {
            // Just add the new content at the end
            let startIndex = newText.index(newText.startIndex, offsetBy: oldText.count)
            return String(newText[startIndex...])
        }
        
        // Method 2: If old text is really different, just use whole new text
        // This handles the case where model completely changes its prediction
        if newText.count > oldText.count * 2 || !oldText.isEmpty && !newText.contains(oldText) {
            return newText
        }
        
        // Method 3: Simple diff calculation
        var i = 0
        while i < min(oldText.count, newText.count) {
            let oldIndex = oldText.index(oldText.startIndex, offsetBy: i)
            let newIndex = newText.index(newText.startIndex, offsetBy: i)
            
            if oldText[oldIndex] != newText[newIndex] {
                break
            }
            i += 1
        }
        
        // If all characters matched, but new text is longer, return the remainder
        if i == oldText.count && newText.count > oldText.count {
            let startIndex = newText.index(newText.startIndex, offsetBy: i)
            return String(newText[startIndex...])
        }
        
        // If we can't figure out what's new, just return empty
        return ""
    }
    
    /// Insert partial transcription in real-time
    private func insertPartialTranscription(_ text: String) {
        guard !text.isEmpty else { return }
        
        Swift.print("REAL-TIME: Inserting partial text: \"\(text)\"")
        
        // CRITICAL FIX: Insert text at cursor IMMEDIATELY
        // Check if we're already on the main thread
        if Thread.isMainThread {
            // Already on main thread, execute directly
            Swift.print("REAL-TIME: Already on main thread, inserting NOW")
            let success = insertTextAtCursor(text)
            
            if !success {
                Swift.print("REAL-TIME: Primary insertion failed, trying direct typing...")
                _ = typeTextDirectly(text)
            } else {
                Swift.print("REAL-TIME: Text inserted successfully!")
            }
        } else {
            // Need to switch to main thread
            DispatchQueue.main.async {
                Swift.print("REAL-TIME: Switching to main thread to insert NOW")
                let success = insertTextAtCursor(text)
                
                if !success {
                    Swift.print("REAL-TIME: Primary insertion failed, trying direct typing...")
                    _ = typeTextDirectly(text)
                } else {
                    Swift.print("REAL-TIME: Text inserted successfully!")
                }
            }
        }
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
            
            Swift.print("Recording started...")
            if let statusItem = self.statusItem, let button = statusItem.button {
                button.title = self.recordingIcon
            }
            
            guard let recorder = self.recorder else {
                Swift.print("ERROR: Recorder not initialized")
                return
            }
            
            guard let transcriber = self.whisperTranscriber else {
                Swift.print("ERROR: Transcriber not initialized")
                return
            }
            
            // Reset current transcription
            self.currentTranscription = ""
            self.previousTranscription = ""
            
            // Start streaming transcription
            recorder.startStreamingRecording(with: transcriber)
            
            self.isRecording = true
        }
        
        // Key up handler - stop recording and process transcription
        hotKey.keyUpHandler = { [weak self] in
            guard let self = self else {
                Swift.print("ERROR: Self is nil in keyUpHandler")
                return
            }
            
            guard self.isRecording else {
                Swift.print("WARNING: Key up received but not recording - ignoring")
                return
            }
            
            Swift.print("Recording stopped. Finalizing transcription...")
            
            // Update UI to show processing state
            if let statusItem = self.statusItem, let button = statusItem.button {
                button.title = self.processingIcon
                button.toolTip = "Processing transcription..."
            }
            
            self.isRecording = false
            
            // Check recorder is valid
            guard let recorder = self.recorder else {
                Swift.print("ERROR: Audio recorder is nil")
                return
            }
            
            // Create a task to finalize the transcription but now we'll handle final insertion differently
            // since we're already inserting text in real-time
            Task {
                Swift.print("KEYUP HANDLER: Stopping recording and waiting for final transcription...")
                
                // Store what we have already inserted up to this point
                // We're using previousTranscription which is already tracking what we've inserted
                // This prevents duplications between the real-time insertions and final insertions
                
                // Stop the streaming transcription first
                recorder.stopRecording()
                
                // Set a delay to allow for final transcription processing
                Swift.print("KEYUP HANDLER: Waiting for final transcription to complete...")
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 second delay
                
                // No need to insert anything else at key-up since we're already inserting in real-time
                // The transcriptionDidUpdate delegate will handle the final transcription as well
                Swift.print("KEYUP HANDLER: Recording stopped, real-time insertion complete")
                
                // Update UI back to normal
                DispatchQueue.main.async {
                    if let statusItem = self.statusItem, let button = statusItem.button {
                        button.title = self.micIcon
                        button.toolTip = "StageWhisper - Press ⌘⇧Z to dictate"
                    }
                }
            }
        }
        
        // Log ready state
        Swift.print("Ready to record. Press \(Config.hotkeyModifiers.description)+\(Config.hotkeyKey.description) to dictate.")
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
    
    // Store a reference to the dictation delegate using a static property to keep it alive
    let _ = dictationDelegate // Force strong reference to prevent deallocation
    objc_setAssociatedObject(NSApplication.shared, "dictationDelegate", dictationDelegate, .OBJC_ASSOCIATION_RETAIN)
    
    // Since we're already running within the NSApplication context,
    // we just need to register our dictation delegate to handle the UI
    NSApplication.shared.activate(ignoringOtherApps: true)
    
    // Initialize the delegate
    dictationDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    
    print("Menu bar app started - look for the 🎤 icon in your menu bar")
}