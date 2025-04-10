// ABOUTME: WhisperKit implementation for audio transcription
// ABOUTME: Provides speech recognition using the WhisperKit library

import Foundation
import AVFoundation
import WhisperKit

/// A simple wrapper for WhisperKit transcription functionality
class WhisperTranscriber {
    private var whisperKit: WhisperKit?
    private var modelFolder: String
    private var isModelLoaded = false
    
    init(modelFolder: String) {
        // Ensure we have an absolute path with tilde expansion
        let expandedPath = (modelFolder as NSString).expandingTildeInPath
        self.modelFolder = expandedPath  // Store the expanded path
        
        // Create model directory if needed
        if !FileManager.default.fileExists(atPath: expandedPath) {
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: expandedPath),
                                              withIntermediateDirectories: true)
        }
    }
    
    /// Load the WhisperKit model
    /// - Parameter forceDownload: Whether to force a fresh download even if the model exists
    /// - Returns: Whether the model loaded successfully
    func loadModel(forceDownload: Bool = false) async -> Bool {
        guard !isModelLoaded else { return true }
        
        let fileManager = FileManager.default
        
        print("Loading Whisper model from \(modelFolder)")
        
        // Create directory if needed
        if !fileManager.fileExists(atPath: modelFolder) {
            do {
                try fileManager.createDirectory(at: URL(fileURLWithPath: modelFolder),
                                          withIntermediateDirectories: true)
                print("Created model directory: \(modelFolder)")
            } catch {
                print("WARNING: Could not create model directory: \(error)")
            }
        }
        
        do {
            print("Initializing WhisperKit with model: large-v3")
            
            // First try to download the model with progress reporting
            do {
                print("Downloading model files (this may take a few minutes)...")
                try await WhisperKit.download(
                    variant: "large-v3",
                    useBackgroundSession: false,
                    progressCallback: { progress in
                        let percentComplete = Int(progress.fractionCompleted * 100)
                        print("Download progress: \(percentComplete)% complete")
                        
                        // Also report via notification for menu bar updates
                        self.reportProgress(
                            progress: progress.fractionCompleted,
                            status: "Downloading model files (\(percentComplete)%)"
                        )
                    }
                )
                print("Model download complete!")
            } catch {
                print("Note: Download step skipped or failed: \(error.localizedDescription)")
                print("Will attempt to use existing model files if available.")
            }
            
            // Initialize WhisperKit with the model
            let config = WhisperKitConfig(model: "large-v3")
            whisperKit = try await WhisperKit(config)
            
            print("WhisperKit initialization complete")
            
            isModelLoaded = true
            print("WhisperKit initialized successfully")
            return true
        } catch {
            print("ERROR: Failed to initialize WhisperKit: \(error)")
            print("Detailed error: \(String(describing: error))")
            return false
        }
    }
    
    /// Report download progress via notification center
    private func reportProgress(progress: Double, status: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("WhisperKitDownloadProgress"),
                object: nil,
                userInfo: [
                    "progress": progress,
                    "status": status
                ]
            )
        }
    }
    
    /// Show download progress in console
    private func showProgress(_ progress: Double, _ message: String) {
        print("Download: \(Int(progress * 100))% - \(message)")
    }
    
    /// Transcribe audio from a file URL
    /// - Parameter url: URL to the audio file
    /// - Returns: Transcribed text or nil if failed
    func transcribeAudioFile(at url: URL) async -> String? {
        // Verify audio file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("ERROR: Audio file does not exist at path: \(url.path)")
            return nil
        }
        
        print("Starting transcription of audio file: \(url.path)")
        
        // Ensure WhisperKit model is loaded
        guard await loadModel() else {
            print("ERROR: WhisperKit model is not loaded. Aborting transcription.")
            print("You need to download the actual WhisperKit model files to use this feature.")
            print("See: https://huggingface.co/argmaxinc/whisperkit-coreml")
            return nil
        }
        
        guard let whisperKit = self.whisperKit else {
            print("ERROR: WhisperKit instance is nil. Aborting transcription.")
            return nil
        }
        
        do {
            print("Transcribing audio with WhisperKit...")
            let results = try await whisperKit.transcribe(audioPath: url.path)
            
            // WhisperKit returns an array of TranscriptionResult, get the combined text
            if results.isEmpty {
                print("WARNING: WhisperKit returned empty results array")
                return nil
            }
            
            // Join all segments text from the first result
            let combinedText = results[0].text
            print("Transcription successful: \"\(combinedText)\"")
            return combinedText
            
        } catch {
            print("ERROR: Failed to transcribe audio with WhisperKit: \(error)")
            return nil
        }
    }
}

/// Extension to expose options to WhisperTranscriber
extension WhisperTranscriber {
    /// Create a default transcriber using the app's configuration
    static func createDefault() -> WhisperTranscriber {
        // Default model directory from config
        let modelDir = Config.whisperModelPath
        
        return WhisperTranscriber(modelFolder: modelDir)
    }
}