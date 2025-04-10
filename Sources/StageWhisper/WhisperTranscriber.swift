// ABOUTME: WhisperKit implementation for audio transcription
// ABOUTME: Provides speech recognition using the WhisperKit library with live transcription

import Foundation
import AVFoundation
@preconcurrency import WhisperKit

/// Protocol for streaming transcription updates
protocol TranscriptionDelegate: AnyObject {
    func transcriptionDidUpdate(text: String, isFinal: Bool)
    func transcriptionDidError(error: Error)
}

/// A comprehensive wrapper for WhisperKit transcription functionality
class WhisperTranscriber {
    private var whisperKit: WhisperKit?
    private var modelFolder: String
    private var isModelLoaded = false
    private var isTranscribing = false
    private var currentTranscription = ""
    
    // Audio engine to capture input
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    // Buffer for captured audio
    private var shouldRecord = false
    private var audioBuffer = [Float]()
    private var processingTask: Task<Void, Error>?
    private var lastProcessTime: Date?
    private var speechDetected = false
    private var energyThreshold: Float = 0.01 // Threshold for speech detection
    
    // Settings - optimized for lowest latency
    private let bufferTimeInterval: TimeInterval = 0.75 // Process 0.75 seconds of audio at a time
    private let minProcessInterval: TimeInterval = 0.3 // Minimum time between processing runs
    private let maxProcessInterval: TimeInterval = 0.8 // Maximum time between processing runs
    
    /// Delegate to receive transcription updates
    weak var delegate: TranscriptionDelegate?
    
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
        
        // Try several models in order of preference, prioritizing lowest latency
        let modelsToTry = [
            "distil-whisper_distil-small-v3_turbo_100MB",  // Fastest model with decent quality (~100MB)
            "tiny.en",                                     // Ultra fast English-only model (~40MB)
            "distil-whisper_distil-medium-v3_turbo_300MB", // Good balance of speed and quality
            "tiny"                                         // Final fallback
        ]
        
        for (index, modelName) in modelsToTry.enumerated() {
            do {
                // Clear any previous attempt
                whisperKit = nil
                
                print("Initializing WhisperKit with model: \(modelName) (attempt \(index + 1) of \(modelsToTry.count))")
                
                // First try to download the model with progress reporting
                do {
                    print("Downloading model files (this may take a few minutes)...")
                    let modelURL = try await WhisperKit.download(
                        variant: modelName,
                        useBackgroundSession: false,
                        progressCallback: { progress in
                            let percentComplete = Int(progress.fractionCompleted * 100)
                            print("Download progress: \(percentComplete)% complete")
                            
                            // Also report via notification for menu bar updates
                            self.reportProgress(
                                progress: progress.fractionCompleted,
                                status: "Downloading \(modelName) (\(percentComplete)%)"
                            )
                        }
                    )
                    print("Model download complete! Model at: \(modelURL.path)")
                    
                    // Initialize WhisperKit with the model
                    let config = WhisperKitConfig(model: modelName)
                    
                    // Report loading phase
                    self.reportProgress(
                        progress: 1.0,
                        status: "Loading model \(modelName)..."
                    )
                    
                    // Initialize WhisperKit with timeout
                    var initSuccess = false
                    let initTask = Task {
                        whisperKit = try await WhisperKit(config)
                    }
                    
                    do {
                        // Set a 30-second timeout for initialization
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask {
                                try await initTask.value
                            }
                            
                            group.addTask {
                                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds timeout
                                if !initTask.isCancelled {
                                    initTask.cancel()
                                    throw NSError(domain: "WhisperTranscriber", code: 98, 
                                              userInfo: [NSLocalizedDescriptionKey: "Model initialization timed out"])
                                }
                            }
                            
                            // Wait for first task to complete
                            try await group.next()
                            group.cancelAll()
                            initSuccess = true
                        }
                    } catch {
                        print("ERROR during WhisperKit initialization: \(error)")
                        continue // Try next model
                    }
                    
                    guard initSuccess, whisperKit != nil else {
                        print("WhisperKit initialization failed, trying next model...")
                        continue
                    }
                    
                    // Load models with timeout
                    if whisperKit?.modelState != .loaded {
                        print("Models not fully loaded, current state: \(String(describing: whisperKit?.modelState))")
                        print("Starting explicit model loading...")
                        
                        do {
                            // Try to load models with timeout
                            var loadSuccess = false
                            try await withThrowingTaskGroup(of: Bool.self) { group in
                                // Model loading task
                                group.addTask {
                                    do {
                                        let startTime = Date()
                                        print("Begin loading models at \(startTime)")
                                        try await self.whisperKit?.loadModels()
                                        let endTime = Date()
                                        let duration = endTime.timeIntervalSince(startTime)
                                        print("Model loading completed in \(String(format: "%.2f", duration)) seconds")
                                        return true
                                    } catch {
                                        print("ERROR loading models: \(error)")
                                        return false
                                    }
                                }
                                
                                // Timeout task
                                group.addTask {
                                    try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                                    print("WARNING: Model loading timeout task triggered")
                                    return false
                                }
                                
                                // Take the first completed task's result
                                if let result = try await group.next() {
                                    loadSuccess = result
                                    group.cancelAll() // Cancel other tasks
                                }
                            }
                            
                            if !loadSuccess {
                                print("WARNING: Model loading timed out or failed")
                                continue // Try next model
                            }
                        } catch {
                            print("ERROR during model loading: \(error)")
                            continue // Try next model
                        }
                    }
                    
                    // Verify tokenizer is available
                    if whisperKit?.tokenizer == nil {
                        print("WARNING: Tokenizer is not available after loading!")
                        continue // Try next model
                    }
                    
                    print("WhisperKit initialization complete - final state: \(String(describing: whisperKit?.modelState))")
                    
                    isModelLoaded = true
                    print("WhisperKit initialized successfully with model: \(modelName)")
                    return true
                } catch {
                    print("ERROR during model download: \(error.localizedDescription)")
                    continue // Try next model
                }
            }
        }
        
        // If we got here, none of the models worked
        print("ERROR: Failed to initialize WhisperKit with any model")
        return false
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
    
    /// Start streaming transcription from the audio engine
    /// - Parameter audioEngine: The AVAudioEngine to capture audio from
    /// - Returns: Success status
    func startStreamingTranscription(audioEngine: AVAudioEngine) -> Bool {
        guard !isTranscribing else {
            print("ERROR: Already transcribing")
            return false
        }
        
        guard whisperKit != nil else {
            print("ERROR: WhisperKit not initialized")
            return false
        }
        
        self.audioEngine = audioEngine
        self.inputNode = audioEngine.inputNode
        
        // Reset current transcription
        currentTranscription = ""
        
        // Start capturing audio
        do {
            // Configure audio buffer and processing
            shouldRecord = true
            audioBuffer.removeAll()
            
            // Install tap on input node to capture audio
            let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
            audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self, self.shouldRecord else { return }
                
                // Process the buffer for transcription
                let audioBuffer = self.getChannelDataFromBuffer(buffer)
                
                // Assuming a 16kHz model input requirement, handle sample rate conversion if needed
                if buffer.format.sampleRate != Float64(Config.sampleRate) {
                    // Simple resampling - in production code you'd want a proper resampler
                    let step = buffer.format.sampleRate / Float64(Config.sampleRate)
                    let resampledBuffer = self.resampleBuffer(audioBuffer, step: Float(step))
                    self.processAudioForTranscription(resampledBuffer)
                } else {
                    self.processAudioForTranscription(audioBuffer)
                }
            }
            
            // Start the audio engine
            audioEngine.prepare()
            try audioEngine.start()
            
            isTranscribing = true
            print("Started streaming transcription")
            
            // Start a task to process audio in chunks with adaptive timing
            processingTask = Task {
                // Start processing almost immediately - just minimal delay to allow first audio samples
                try await Task.sleep(nanoseconds: 50_000_000) // Wait just 50ms before first processing
                print("CRITICAL: Starting first transcription processing run")
                
                lastProcessTime = Date()
                
                while isTranscribing && !Task.isCancelled {
                    // Start processing with almost any amount of audio data
                    if audioBuffer.count > Config.sampleRate / 32 { // Just 0.03s of audio to start processing 
                        print("CRITICAL: Have \(audioBuffer.count) samples, starting transcription cycle")
                        // Check if speech is detected to adjust processing frequency
                        speechDetected = detectSpeech(in: audioBuffer)
                        
                        // Determine if we should process now based on speech detection and timing
                        let now = Date()
                        let timeSinceLastProcess = now.timeIntervalSince(lastProcessTime ?? Date(timeIntervalSince1970: 0))
                        
                        let shouldProcessNow = speechDetected
                            ? timeSinceLastProcess >= minProcessInterval  // Process more frequently during speech
                            : timeSinceLastProcess >= maxProcessInterval   // Process less frequently during silence
                        
                        if shouldProcessNow {
                            if !Task.isCancelled {
                                // Process the buffer and update timestamp
                                await self.processCurrentBuffer()
                                lastProcessTime = Date()
                            }
                        }
                    }
                    
                    // Brief delay before checking again - quick polling
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms polling interval
                }
            }
            
            return true
        } catch {
            print("ERROR: Failed to start streaming transcription: \(error)")
            delegate?.transcriptionDidError(error: error)
            return false
        }
    }
    
    /// Handle and accumulate incoming audio data
    private func processAudioForTranscription(_ samples: [Float]) {
        // Append to the buffer
        audioBuffer.append(contentsOf: samples)
        
        // Cap buffer size to avoid excessive memory usage (30 seconds max)
        let maxBufferSize = Config.sampleRate * 30
        if audioBuffer.count > maxBufferSize {
            audioBuffer.removeFirst(audioBuffer.count - maxBufferSize)
        }
    }
    
    /// Process the current audio buffer for transcription
    private func processCurrentBuffer() async {
        guard isTranscribing, let whisperKit = whisperKit else { return }
        
        // Make a copy of the buffer to avoid race conditions
        // Get the last N seconds of audio for transcription (sliding window)
        let bufferSizeToTranscribe = min(Int(bufferTimeInterval * Double(Config.sampleRate)), audioBuffer.count)
        
        // Start processing with minimal audio - we need immediate feedback
        // Process with as little as 0.1 seconds of audio
        guard bufferSizeToTranscribe > Config.sampleRate / 10 else { 
            print("CRITICAL: Buffer too small to process: \(bufferSizeToTranscribe) samples")
            return 
        }
        
        print("CRITICAL: Processing \(bufferSizeToTranscribe) samples")
        
        let startIndex = max(0, audioBuffer.count - bufferSizeToTranscribe)
        let bufferCopy = Array(audioBuffer[startIndex...])
        
        do {
            // Ultra low-latency optimized options
            let options = DecodingOptions(
                task: .transcribe,
                temperature: 0,
                sampleLength: min(150, max(40, bufferSizeToTranscribe / 100)), // Smaller sample length for faster decoding
                skipSpecialTokens: true,
                withoutTimestamps: true,
                compressionRatioThreshold: 1.8,  // Lower threshold for faster processing
                logProbThreshold: -0.6,          // More permissive for partial utterances
                noSpeechThreshold: 0.6           // More permissive to detect speech sooner
            )
            
            let results = try await whisperKit.transcribe(audioArray: bufferCopy, decodeOptions: options)
            
            // Process transcription results
            if !results.isEmpty, let result = results.first, !result.text.isEmpty {
                // Update current transcription
                currentTranscription = result.text
                
                // Notify delegate
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.transcriptionDidUpdate(text: result.text, isFinal: false)
                }
                
                // Log the result
                if Config.verbose {
                    print("Transcription update: \"\(result.text)\"")
                }
            }
        } catch {
            print("ERROR during transcription: \(error)")
        }
    }
    
    /// Stop streaming transcription
    func stopStreamingTranscription() async {
        guard isTranscribing else {
            print("WARNING: Not currently transcribing")
            return
        }
        
        print("Stopping streaming transcription and processing final output...")
        
        isTranscribing = false
        shouldRecord = false
        
        // Cancel the processing task
        processingTask?.cancel()
        
        // Clean up the audio tap
        if let inputNode = inputNode {
            inputNode.removeTap(onBus: 0)
        }
        
        // Process final transcription with the complete buffer
        if !audioBuffer.isEmpty, let whisperKit = whisperKit {
            do {
                print("Processing final transcription with \(audioBuffer.count) samples...")
                
                // For final transcription, use more thorough settings
                let options = DecodingOptions(
                    task: .transcribe,
                    temperature: 0,
                    sampleLength: 280, // Larger sample length for better quality in final transcription
                    skipSpecialTokens: true,
                    withoutTimestamps: true,
                    compressionRatioThreshold: 2.4, // Higher threshold for final since we want better quality
                    logProbThreshold: -0.4, // More permissive log prob threshold
                    noSpeechThreshold: 0.4  // More permissive no speech threshold
                )
                
                let results = try await whisperKit.transcribe(audioArray: audioBuffer, decodeOptions: options)
                
                if !results.isEmpty, let result = results.first {
                    let finalText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Update current transcription
                    currentTranscription = finalText
                    
                    // Notify delegate
                    DispatchQueue.main.async { [weak self] in
                        print("FINAL RESULT: Calling delegate with final transcription")
                        self?.delegate?.transcriptionDidUpdate(text: finalText, isFinal: true)
                    }
                    
                    // Log the result
                    print("TRANSCRIBER: Final transcription: \"\(finalText)\"")
                } else {
                    print("WARNING: No text found in final transcription results")
                }
            } catch {
                print("ERROR during final transcription: \(error)")
                delegate?.transcriptionDidError(error: error)
            }
        } else {
            print("WARNING: Audio buffer is empty or WhisperKit is nil - no final transcription possible")
        }
        
        // Reset buffer to free memory
        audioBuffer.removeAll()
        
        print("Stopped streaming transcription")
    }
    
    /// Get the current transcription text
    /// - Returns: The current transcription
    func getCurrentTranscription() -> String {
        return currentTranscription
    }
    
    /// Transcribe audio from a file URL (non-streaming mode)
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
    
    // MARK: - Helper methods
    
    /// Detect if there's speech in the audio buffer
    private func detectSpeech(in buffer: [Float]) -> Bool {
        // Simple energy-based voice activity detection
        let samples = min(buffer.count, 3200) // Look at ~0.2s of audio (at 16kHz)
        let startIdx = max(0, buffer.count - samples)
        
        var energy: Float = 0
        for i in startIdx..<buffer.count {
            energy += buffer[i] * buffer[i]
        }
        
        // Calculate average energy
        energy /= Float(samples)
        
        // Adaptive threshold adjustment - makes the system more sensitive over time
        if energy > energyThreshold {
            // Quickly adapt when speech is detected
            energyThreshold = min(energyThreshold * 1.1, 0.05)
            return true
        } else {
            // Slowly decrease threshold during silence to become more sensitive
            energyThreshold = max(energyThreshold * 0.98, 0.005)
            return false
        }
    }
    
    /// Extract audio data from an AVAudioPCMBuffer
    private func getChannelDataFromBuffer(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Create array to hold the data
        var samples = [Float]()
        
        if let floatData = buffer.floatChannelData {
            // Get data from first channel
            let channelData = floatData[0]
            
            // Copy the samples
            for i in 0..<frameCount {
                samples.append(channelData[i])
            }
            
            // If stereo, average the channels
            if channelCount > 1 {
                for channel in 1..<min(channelCount, 2) {
                    let additionalChannelData = floatData[channel]
                    for i in 0..<frameCount {
                        samples[i] = (samples[i] + additionalChannelData[i]) / 2.0
                    }
                }
            }
        }
        
        return samples
    }
    
    /// Resample audio buffer for different sample rates
    private func resampleBuffer(_ buffer: [Float], step: Float) -> [Float] {
        var resampled = [Float]()
        var i: Float = 0
        while i < Float(buffer.count) {
            let index = Int(i)
            if index < buffer.count {
                resampled.append(buffer[index])
            }
            i += step
        }
        return resampled
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