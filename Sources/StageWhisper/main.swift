// ABOUTME: Entry point for the StageWhisper app with menu bar support.
// ABOUTME: Inserts text at the current cursor position using macOS Accessibility APIs with dictation support.

import Foundation
import AppKit
import ApplicationServices
import HotKey
import AVFoundation

// MARK: - Constants and Configuration

struct Config {
    static let hotkeyKey: Key = .z
    static let hotkeyModifiers: NSEvent.ModifierFlags = [.command, .shift]
    static let sampleRate = 16000
    static let tempAudioPath = NSTemporaryDirectory().appending("swift_insert_recording.wav")
    static var verbose = false
    // Create a folder within the app directory for easier management
    static let whisperModelPath = NSHomeDirectory() + "/Library/Application Support/StageWhisper/Models"
    // Model will be auto-downloaded by WhisperKit
}

// MARK: - Text Insertion Logic

func insertTextAtCursor(_ text: String) -> Bool {
    // Get the system-wide AXUIElement
    let systemWideElement = AXUIElementCreateSystemWide()
    
    // Get the focused application
    var focusedApp: AnyObject?
    let focusedAppResult = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedApplicationAttribute as CFString, &focusedApp)
    
    if focusedAppResult != .success || focusedApp == nil {
        print("Error: Could not get focused application (error code: \(focusedAppResult.rawValue))")
        print("Make sure Terminal has Accessibility permissions")
        return false
    }
    
    guard let focusedApplication = focusedApp else {
        print("Error: Focused application is nil")
        return false
    }
    
    // Safety check for the right type
    guard CFGetTypeID(focusedApplication) == AXUIElementGetTypeID() else {
        print("Error: Focused application is not an accessibility element")
        return false
    }
    
    let focusedAXElement = focusedApplication as! AXUIElement
    
    // Get the focused element in the application
    var focusedElement: AnyObject?
    let focusedElementResult = AXUIElementCopyAttributeValue(focusedAXElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
    
    guard focusedElementResult == .success, let focusedElementObj = focusedElement else {
        print("Error: Could not get focused UI element")
        return false
    }
    
    guard CFGetTypeID(focusedElementObj) == AXUIElementGetTypeID() else {
        print("Error: Focused element is not an accessibility element")
        return false
    }
    
    // We confirmed the element is valid, so we can proceed with insertion
    
    // Save the current clipboard contents
    let pasteboard = NSPasteboard.general
    let oldContents = pasteboard.string(forType: .string)
    
    // Set the pasteboard contents to our text
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    
    // Simulate Command+V keystroke
    let cmdV = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true) // V key
    cmdV?.flags = .maskCommand
    cmdV?.post(tap: .cghidEventTap)
    
    // Release keys
    let cmdVUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
    cmdVUp?.post(tap: .cghidEventTap)
    
    // Wait a moment
    Thread.sleep(forTimeInterval: 0.1)
    
    // Restore original clipboard if it existed
    pasteboard.clearContents()
    if let oldContents = oldContents {
        pasteboard.setString(oldContents, forType: .string)
    }
    
    return true
}

// Method 2: Using CGEventPost to simulate typing directly
func typeTextDirectly(_ text: String) -> Bool {
    let source = CGEventSource(stateID: .combinedSessionState)
    
    // Ensure we have a valid event source
    guard let source = source else {
        print("Error: Could not create event source")
        return false
    }
    
    for character in text {
        // Convert character to UniChar
        let string = String(character)
        guard let firstUniChar = string.utf16.first else { continue }
        
        // Create keyboard events for key down and up
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: [firstUniChar])
            down.post(tap: .cghidEventTap)
            
            // Small delay between keypresses
            usleep(5000) // 5ms delay
            
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.post(tap: .cghidEventTap)
            }
        }
    }
    
    return true
}

// MARK: - Audio Recording

class AudioRecorder {
    // Audio engine and format
    private let audioEngine = AVAudioEngine()
    private let outputFormat: AVAudioFormat
    
    // Recording state
    private var isRecording = false
    private var bufferList: [AVAudioPCMBuffer] = []
    
    // Transcriber reference
    private var transcriber: WhisperTranscriber?
    
    // Callbacks for events
    var onStreamingStart: (() -> Void)?
    var onStreamingStop: (() -> Void)?
    
    init() {
        // Configure audio format for Whisper (16kHz mono PCM)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Config.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,  // Using 32-bit float to avoid conversion issues
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        guard let format = AVAudioFormat(settings: settings) else {
            fatalError("Could not create audio format")
        }
        
        self.outputFormat = format
        
        // No audio session setup needed on macOS
    }
    
    // Start recording with streaming transcription
    func startStreamingRecording(with transcriber: WhisperTranscriber) {
        self.transcriber = transcriber
        
        print("CRITICAL: Starting audio recording for streaming transcription")
        
        // Start the transcription IMMEDIATELY 
        if !transcriber.startStreamingTranscription(audioEngine: audioEngine) {
            print("ERROR: Failed to start streaming transcription")
            return
        }
        
        print("CRITICAL: Transcription engine started successfully")
        
        // Signal that streaming has started
        onStreamingStart?()
        
        isRecording = true
        
        // Force a log flush to make sure we see the logs right away
        fflush(stdout)
    }
    
    // Stop recording and clean up resources
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        
        // Stop audio engine
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Stop the transcriber
        if let transcriber = self.transcriber {
            Task {
                print("Recording stopped. Finalizing transcription...")
                await transcriber.stopStreamingTranscription()
                
                // Call the stop callback after async operation completes
                DispatchQueue.main.async { [weak self] in
                    self?.onStreamingStop?()
                }
            }
        } else {
            // No transcriber, just call the callback directly
            onStreamingStop?()
        }
        
        if Config.verbose {
            print("Stopped recording and transcription")
        }
    }
    
    // No file saving needed for streaming mode
    
    // Get the audio engine (needed for streaming)
    func getAudioEngine() -> AVAudioEngine {
        return audioEngine
    }
}

// MARK: - Check Microphone Access

func checkMicrophoneAccess(completion: @escaping (Bool) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
        completion(true)
    case .notDetermined:
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    case .denied, .restricted:
        completion(false)
    @unknown default:
        completion(false)
    }
}

// MARK: - Whisper Transcription

/// Transcribe audio using WhisperKit (for backward compatibility)
func transcribeAudio(at url: URL) async -> String? {
    if Config.verbose {
        print("Transcribing audio at: \(url.path)")
    }
    
    // Create a transcriber
    let transcriber = WhisperTranscriber.createDefault()
    
    // Transcribe audio
    return await transcriber.transcribeAudioFile(at: url)
}

// Simplified function to start dictation mode
func startDictationMode() {
    // This function uses the implementation in MenuBarApp.swift
    startDictationApp()
}

// MARK: - Main Program

func requestPermissions() -> Bool {
    // Request accessibility permissions
    let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
    let options = [checkOptPrompt: true] as CFDictionary
    let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
    
    if !accessibilityEnabled {
        print("ERROR: Accessibility permissions required")
        print("Please grant Terminal app Accessibility permissions in:")
        print("System Settings > Privacy & Security > Accessibility")
        print("\nThen try running the command again.")
        return false
    }
    
    // Add a small delay to ensure accessibility connection is established
    Thread.sleep(forTimeInterval: 0.5)
    
    return true
}

// Create an NSApplicationDelegate class to handle application launch
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Always start in dictation mode (this is a GUI app)
        print("Starting StageWhisper...")
        print("Models will be automatically downloaded if needed")
        
        // Set verbose mode for now (helpful during development)
        Config.verbose = true
        
        // Start dictation mode
        startDictationMode()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("StageWhisper is shutting down...")
    }
}

// Since we're building as a command-line tool but want to run as an app,
// we need to manually set up the application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Run the app without a dock icon
app.setActivationPolicy(.accessory)

// Start the application
app.run()