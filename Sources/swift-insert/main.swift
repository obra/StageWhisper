// ABOUTME: Entry point for the swift-insert tool with menu bar support.  
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
    static let whisperModelPath = NSHomeDirectory() + "/Library/Application Support/SwiftInsert/Models"
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
    private let audioEngine = AVAudioEngine()
    private let outputFormat: AVAudioFormat
    private var audioFile: AVAudioFile?
    private var isRecording = false
    private var bufferList: [AVAudioPCMBuffer] = []
    
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
    }
    
    func startRecording() {
        // Delete any existing recording
        if FileManager.default.fileExists(atPath: Config.tempAudioPath) {
            try? FileManager.default.removeItem(atPath: Config.tempAudioPath)
        }
        
        // Clear buffer list
        bufferList.removeAll()
        
        do {
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            
            if Config.verbose {
                print("Input format: \(inputFormat)")
                print("Output format: \(outputFormat)")
            }
            
            // Install tap on input node
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self, self.isRecording else { return }
                
                // Store the buffer for later processing
                self.bufferList.append(buffer)
            }
            
            // Start engine
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            
            if Config.verbose {
                print("Started recording to memory buffer")
            }
            
        } catch {
            if Config.verbose {
                print("Failed to start recording: \(error)")
            }
        }
    }
    
    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        if Config.verbose {
            print("Stopped recording - writing \(bufferList.count) buffers to disk")
        }
        
        // Save the recorded buffers to disk
        guard let fileURL = saveBuffersToDisk() else {
            print("Failed to save audio to disk")
            return nil
        }
        
        return fileURL
    }
    
    private func saveBuffersToDisk() -> URL? {
        guard !bufferList.isEmpty else {
            print("No audio data captured")
            return nil
        }
        
        let fileURL = URL(fileURLWithPath: Config.tempAudioPath)
        
        // Create audio file
        guard let audioFile = try? AVAudioFile(forWriting: fileURL, settings: outputFormat.settings) else {
            print("Failed to create audio file")
            return nil
        }
        
        // Get input format from the first buffer
        let inputFormat = bufferList[0].format
        
        // Process each buffer
        for buffer in bufferList {
            if inputFormat.sampleRate != outputFormat.sampleRate || 
               inputFormat.channelCount != outputFormat.channelCount {
                
                // Need to convert format
                if let converter = AVAudioConverter(from: inputFormat, to: outputFormat) {
                    // Create output buffer
                    let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * (outputFormat.sampleRate / inputFormat.sampleRate))
                    
                    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
                        print("Failed to create output buffer")
                        continue
                    }
                    
                    var error: NSError?
                    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                        outStatus.pointee = .haveData
                        return buffer
                    }
                    
                    let conversionResult = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
                    
                    if let error = error {
                        print("Conversion error: \(error)")
                        continue
                    }
                    
                    if conversionResult == .error {
                        print("Conversion failed")
                        continue
                    }
                    
                    // Write converted buffer to file
                    do {
                        try audioFile.write(from: outputBuffer)
                    } catch {
                        print("Error writing to file: \(error)")
                    }
                }
            } else {
                // Write directly if formats match
                do {
                    try audioFile.write(from: buffer)
                } catch {
                    print("Error writing to file: \(error)")
                }
            }
        }
        
        if Config.verbose {
            print("Successfully saved audio to \(fileURL.path)")
        }
        
        return fileURL
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

func main() {
    let arguments = CommandLine.arguments
    
    // Parse arguments and set verbose flag first
    if arguments.contains("--verbose") {
        Config.verbose = true
        print("Verbose mode enabled")
    }
    
    // Check for help request
    if arguments.contains("--help") || arguments.contains("-h") {
        print("swift-insert - Insert text at cursor position using accessibility APIs")
        print("")
        print("Usage:")
        print("  swift-insert \"text to insert\"     Insert text at cursor position")
        print("  swift-insert --dictate           Start dictation mode (menu bar app)")
        print("  swift-insert --help              Show this help message")
        print("")
        print("Options:")
        print("  --verbose                        Enable verbose logging")
        return
    }
    
    // Check for dictation mode
    if arguments.contains("--dictate") {
        print("Starting dictation mode...")
        print("Models will be automatically downloaded if needed")
        
        // Start dictation mode
        startDictationMode()
        return
    }
    
    // Regular text insertion mode
    if arguments.count < 2 || (arguments.count == 2 && arguments[1] == "--verbose") {
        print("Usage: swift-insert \"text to insert\"")
        print("       swift-insert --dictate [--verbose]")
        print("       swift-insert --help")
        return
    }
    
    // Request accessibility permissions if needed
    if !requestPermissions() {
        return
    }
    
    // Join all arguments with spaces to handle multi-word text
    let textArgStart = arguments.firstIndex(where: { !$0.hasPrefix("--") || $0 == arguments[0] }) ?? 1
    let textToInsert = arguments[textArgStart...].joined(separator: " ")
    
    // Try first method (clipboard)
    if !insertTextAtCursor(textToInsert) {
        print("Trying alternative method...")
        // If the first method fails, try the direct typing method
        if !typeTextDirectly(textToInsert) {
            print("Error: Both insertion methods failed")
            print("Make sure Terminal has Accessibility permissions in:")
            print("System Settings > Privacy & Security > Accessibility")
            exit(1)
        }
    }
}

// Run the program
main()