import Foundation
import CoreMotion
import AVFoundation
import UIKit
import CoreHaptics

class FractalTonesViewModel: ObservableObject {
    private let motionManager = CMMotionManager()
    private var audioEngine: AVAudioEngine?
    private var currentTone: AVAudioPlayerNode?
    private let bitmapAnalyzer: BitmapAnalyzer
    private var cachedScale: [Double]?
    private let motionQueue = OperationQueue()
    private var hapticEngine: CHHapticEngine?
    private var lastKColorsUpdate: Date = Date()
    private let kColorsUpdateDebounce: TimeInterval = 0.5 // Half second debounce
    private var isProcessingKColors: Bool = false
    private var pendingKColorsUpdate: Int?
    
    @Published var currentMovement: Double = 0
    @Published var movementThreshold: Double = 1.0 {
        didSet {
            // Only update slider if the threshold was changed externally
            let newSliderValue = logarithmicToLinear(movementThreshold)
            if abs(newSliderValue - thresholdSliderValue) > 0.001 {
                thresholdSliderValue = newSliderValue
                print("DEBUG: Slider value updated to \(newSliderValue) (threshold: \(movementThreshold) feet)")
            }
        }
    }
    @Published var isProcessing: Bool = false
    @Published var kColors: Int = 4 { // Changed default to 4
        didSet {
            // If we're already processing, store the new value for later
            if isProcessingKColors {
                print("DEBUG: Processing in progress, storing new value: \(kColors)")
                pendingKColorsUpdate = kColors
                return
            }
            
            // Debounce updates
            let now = Date()
            if now.timeIntervalSince(lastKColorsUpdate) < kColorsUpdateDebounce {
                print("DEBUG: Debouncing kColors update from \(oldValue) to \(kColors)")
                // Schedule the update for after the debounce period
                DispatchQueue.main.asyncAfter(deadline: .now() + kColorsUpdateDebounce) { [weak self] in
                    guard let self = self else { return }
                    // Only process if this is still the most recent update
                    if now == self.lastKColorsUpdate {
                        self.processKColorsUpdate()
                    }
                }
                return
            }
            
            lastKColorsUpdate = now
            processKColorsUpdate()
        }
    }
    @Published var quantizationMethod: ColorQuantizationMethod = .uniform { // Changed default to uniform
        didSet {
            bitmapAnalyzer.setQuantizationMethod(quantizationMethod)
            if let image = savedImageData.flatMap(UIImage.init) {
                // Process image on background thread
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.bitmapAnalyzer.loadImage(image)
                    
                    // Update UI on main thread
                    DispatchQueue.main.async {
                        self?.processedImage = self?.bitmapAnalyzer.getProcessedImage()
                        self?.updateScale()
                    }
                }
            }
        }
    }
    @Published var savedImageData: Data? {
        didSet {
            if let data = savedImageData {
                UserDefaults.standard.set(data, forKey: "lastImageData")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastImageData")
            }
        }
    }
    @Published var totalAccumulatedDistance: Double = 0  // New property for total distance
    @Published var processedImage: UIImage? // New property for the processed image
    
    private var lastPosition: SIMD3<Double> = SIMD3(0, 0, 0)
    private var totalMovement: Double = 0  // This now tracks movement since last tone
    private var isInitialLoad = true
    
    // Base E flat scale frequencies (in Hz)
    private let baseEFlatScale = [
        311.13, // Eb3
        349.23, // F3
        392.00, // G3
        415.30, // Ab3
        466.16, // Bb3
        523.25, // C4
        587.33, // D4
        622.25  // Eb4
    ]
    
    // Constants for threshold scaling
    private let minThreshold: Double = 1.0   // Minimum threshold in feet
    private let maxThreshold: Double = 200.0 // Maximum threshold in feet
    private let stepMultiplier: Double = 1.2 // Each step is 20% larger than the previous
    
    // Linear slider value (0.0 to 1.0)
    @Published var thresholdSliderValue: Double = 0.0 {
        didSet {
            // Convert linear slider value to logarithmic threshold
            let newThreshold = linearToLogarithmic(thresholdSliderValue)
            if newThreshold != movementThreshold {
                movementThreshold = newThreshold
                print("DEBUG: Threshold updated to \(newThreshold) feet (slider value: \(thresholdSliderValue))")
            }
        }
    }
    
    // Computed property to get the appropriate scale based on quantization method
    private var currentScale: [Double] {
        if quantizationMethod == .direct {
            // For direct mapping, we need to scale the frequencies to match the number of unique colors
            let numColors = bitmapAnalyzer.getUniqueColorCount()
            print("DEBUG: Number of unique colors detected: \(numColors)")
            
            if numColors <= 1 {
                print("DEBUG: Warning - only one or zero colors detected!")
                // If there's only one color, return just the base frequency
                return [baseEFlatScale[0]]
            } else if numColors <= baseEFlatScale.count {
                print("DEBUG: Using \(numColors) frequencies from base scale")
                return Array(baseEFlatScale.prefix(numColors))
            } else {
                print("DEBUG: Scaling frequencies for \(numColors) colors")
                // Scale the frequencies to fill the octave
                let baseFreq = baseEFlatScale[0]
                let octaveFreq = baseEFlatScale.last!
                let freqRange = octaveFreq - baseFreq
                let step = freqRange / Double(numColors - 1)
                
                return (0..<numColors).map { i in
                    baseFreq + (step * Double(i))
                }
            }
        } else {
            // For uniform quantization, use the number of quantized colors (k)
            let numColors = kColors
            print("DEBUG: Using \(numColors) frequencies for uniform quantization")
            
            if numColors <= 1 {
                print("DEBUG: Warning - k is too small!")
                return [baseEFlatScale[0]]
            } else if numColors <= baseEFlatScale.count {
                print("DEBUG: Using \(numColors) frequencies from base scale")
                return Array(baseEFlatScale.prefix(numColors))
            } else {
                print("DEBUG: Scaling frequencies for \(numColors) colors")
                // Scale the frequencies to fill the octave
                let baseFreq = baseEFlatScale[0]
                let octaveFreq = baseEFlatScale.last!
                let freqRange = octaveFreq - baseFreq
                let step = freqRange / Double(numColors - 1)
                
                return (0..<numColors).map { i in
                    baseFreq + (step * Double(i))
                }
            }
        }
    }
    
    init() {
        // Initialize BitmapAnalyzer with current settings
        bitmapAnalyzer = BitmapAnalyzer()
        bitmapAnalyzer.setK(4)  // Explicitly set k to 4
        bitmapAnalyzer.setQuantizationMethod(quantizationMethod)
        
        setupMotionManager()
        setupAudioEngine()
        loadSavedImage()
        
        // Initialize threshold values
        movementThreshold = minThreshold
        thresholdSliderValue = 0.0
        
        // Check motion manager authorization
        if !motionManager.isDeviceMotionAvailable {
            print("Device motion is not available")
        }
        
        // Add observer for color count warning
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleColorCountWarning),
            name: NSNotification.Name("ColorCountWarning"),
            object: nil
        )
    }
    
    deinit {
        stopPlayback()
        audioEngine?.stop()
        audioEngine = nil
        currentTone = nil
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleColorCountWarning(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let actualK = userInfo["actualK"] as? Int,
           let message = userInfo["message"] as? String {
            // Update k on the main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.kColors = actualK
                // Show alert to user
                NotificationCenter.default.post(
                    name: NSNotification.Name("ShowAlert"),
                    object: nil,
                    userInfo: ["message": message]
                )
            }
        }
    }
    
    private func loadSavedImage() {
        if let savedData = UserDefaults.standard.data(forKey: "lastImageData") {
            savedImageData = savedData
            if let image = UIImage(data: savedData) {
                isInitialLoad = true
                loadImage(image)
            }
        }
    }
    
    func loadImage(_ image: UIImage) {
        // Set processing state on main thread
        DispatchQueue.main.async { [weak self] in
            self?.isProcessing = true
        }
        
        // Process image on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.bitmapAnalyzer.loadImage(image)
            
            // Generate processed image
            let processedImage = self?.bitmapAnalyzer.getProcessedImage()
            
            // Update UI on main thread
            DispatchQueue.main.async {
                if let imageData = image.jpegData(compressionQuality: 0.8) {
                    if self?.isInitialLoad == true {
                        self?.isInitialLoad = false
                    } else {
                        self?.savedImageData = imageData
                    }
                }
                self?.processedImage = processedImage
                self?.isProcessing = false
                // Recalculate scale after image is processed
                self?.updateScale()
            }
        }
    }
    
    private func updateScale() {
        if quantizationMethod == .direct {
            // For direct mapping, we need to scale the frequencies to match the number of unique colors
            let numColors = bitmapAnalyzer.getUniqueColorCount()
            print("DEBUG: Number of unique colors detected: \(numColors)")
            
            if numColors <= 1 {
                print("DEBUG: Warning - only one or zero colors detected!")
                // If there's only one color, return just the base frequency
                cachedScale = [baseEFlatScale[0]]
            } else if numColors <= baseEFlatScale.count {
                print("DEBUG: Using \(numColors) frequencies from base scale")
                cachedScale = Array(baseEFlatScale.prefix(numColors))
            } else {
                print("DEBUG: Scaling frequencies for \(numColors) colors")
                // Scale the frequencies to fill the octave
                let baseFreq = baseEFlatScale[0]
                let octaveFreq = baseEFlatScale.last!
                let freqRange = octaveFreq - baseFreq
                let step = freqRange / Double(numColors - 1)
                
                cachedScale = (0..<numColors).map { i in
                    baseFreq + (step * Double(i))
                }
            }
        } else {
            cachedScale = baseEFlatScale
        }
    }
    
    private func setupMotionManager() {
        motionManager.deviceMotionUpdateInterval = 0.1
    }
    
    private func setupAudioEngine() {
        // Configure audio session for background playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // First deactivate the session if it's active
            if audioSession.isOtherAudioPlaying {
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            }
            
            // Configure the session for background playback
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try audioSession.setActive(true)
            
            // Configure audio engine
            audioEngine = AVAudioEngine()
            currentTone = AVAudioPlayerNode()
            
            if let engine = audioEngine, let player = currentTone {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: nil)
                
                // Set up audio engine configuration
                engine.mainMixerNode.outputVolume = 1.0
                
                // Prepare the engine
                engine.prepare()
                
                do {
                    try engine.start()
                    print("DEBUG: Audio engine started successfully")
                } catch {
                    print("DEBUG: Error starting audio engine: \(error)")
                }
            }
            
            print("DEBUG: Audio session configured successfully")
        } catch {
            print("DEBUG: Failed to configure audio session: \(error)")
        }
    }
    
    func startPlayback() {
        print("Starting playback...")
        // Reset only the threshold counter when starting
        totalMovement = 0
        currentMovement = 0
        // Don't reset totalAccumulatedDistance
        
        // Ensure audio session is active
        do {
            let audioSession = AVAudioSession.sharedInstance()
            if !audioSession.isOtherAudioPlaying {
                try audioSession.setActive(true)
            }
        } catch {
            print("DEBUG: Error activating audio session: \(error)")
        }
        
        // Ensure audio engine is running
        if audioEngine?.isRunning == false {
            do {
                try audioEngine?.start()
                print("Audio engine started successfully")
            } catch {
                print("Error starting audio engine: \(error)")
                // Try to recover by reinitializing the audio engine
                setupAudioEngine()
                return
            }
        }
        
        // Configure motion queue
        motionQueue.name = "com.fractaltones.motion"
        motionQueue.maxConcurrentOperationCount = 1
        
        // Start motion updates with the handler
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let motion = motion, error == nil else {
                print("Motion update error: \(error?.localizedDescription ?? "unknown error")")
                return
            }
            
            // Calculate movement using accelerometer data
            let acceleration = motion.userAcceleration
            
            // Calculate instantaneous velocity change
            let velocityChange = sqrt(
                pow(acceleration.x, 2) +
                pow(acceleration.y, 2) +
                pow(acceleration.z, 2)
            )
            
            // Debug print the raw values
            print("Acceleration - x: \(acceleration.x), y: \(acceleration.y), z: \(acceleration.z)")
            print("Velocity change: \(velocityChange)")
            
            // Only count movement above a minimum threshold to avoid drift
            let minThreshold: Double = 0.05 // Lowered threshold for more sensitivity
            if velocityChange > minThreshold {
                // Convert to feet (approximate conversion)
                // Using a smaller scaling factor to make movement more accurate
                let feetMoved = velocityChange * 3.28084 * 0.25 // Reduced scaling factor from 2.5 to 0.25
                
                // Update all published properties on the main thread
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    self.totalMovement += feetMoved
                    self.totalAccumulatedDistance += feetMoved
                    self.currentMovement = self.totalAccumulatedDistance
                    
                    print("Current movement: \(self.currentMovement) feet")
                    print("Movement accumulated: \(feetMoved) feet, Total: \(self.totalAccumulatedDistance)")
                    
                    // Check if we've moved enough to trigger a new tone
                    if self.totalMovement >= self.movementThreshold {
                        print("Threshold reached! Playing tone...")
                        self.playNextTone()
                        self.totalMovement = 0  // Only reset the threshold counter
                    }
                }
            }
        }
        print("Motion updates started")
    }
    
    func stopPlayback() {
        print("Stopping playback...")
        motionManager.stopDeviceMotionUpdates()
        currentTone?.stop()
        // Reset only the threshold counter when stopping
        totalMovement = 0
        currentMovement = 0
        // Don't reset totalAccumulatedDistance
        print("Playback stopped")
    }
    
    private func playNextTone() {
        let toneIndex = bitmapAnalyzer.getNextToneIndex()
        // Use currentScale instead of cachedScale to ensure we have the latest frequencies
        let frequency = currentScale[toneIndex % currentScale.count]
        print("DEBUG: Playing tone at index \(toneIndex) with frequency \(frequency) Hz")
        playTone(frequency: frequency)
    }
    
    private func playTone(frequency: Double) {
        guard let engine = audioEngine, let player = currentTone else {
            print("Audio engine or player not available")
            return
        }
        
        // Ensure audio session is active
        do {
            let audioSession = AVAudioSession.sharedInstance()
            if !audioSession.isOtherAudioPlaying {
                try audioSession.setActive(true)
            }
        } catch {
            print("DEBUG: Error activating audio session: \(error)")
            return
        }
        
        // Ensure engine is running
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("DEBUG: Error starting audio engine: \(error)")
                return
            }
        }
        
        // Stop any existing tone
        player.stop()
        
        // Create a sine wave buffer
        let sampleRate: Double = 44100
        let duration: Double = 0.5
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        
        // Get the engine's output format to ensure channel count matches
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("DEBUG: Failed to create audio buffer")
            return
        }
        
        buffer.frameLength = frameCount
        
        // Fill all channels with the same sine wave
        for channel in 0..<Int(format.channelCount) {
            let channelData = buffer.floatChannelData?[channel]
            for frame in 0..<Int(frameCount) {
                let value = sin(2.0 * .pi * frequency * Double(frame) / sampleRate)
                channelData?[frame] = Float(value)
            }
        }
        
        // Schedule the new buffer with completion handler
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts, .loops]) { [weak self] in
            // Buffer completed
            print("DEBUG: Buffer completed for frequency \(frequency) Hz")
            
            // Ensure audio session stays active
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("DEBUG: Error keeping audio session active: \(error)")
            }
        }
        
        // Play the new tone
        player.play()
        print("DEBUG: Started playing tone at \(frequency) Hz")
    }
    
    // Convert linear slider value (0-1) to logarithmic threshold
    private func linearToLogarithmic(_ linear: Double) -> Double {
        // Ensure input is in valid range
        let clampedLinear = max(0.0, min(1.0, linear))
        
        // Calculate the number of steps needed to go from min to max
        let totalSteps = log(maxThreshold / minThreshold) / log(stepMultiplier)
        
        // Calculate the current step
        let currentStep = clampedLinear * totalSteps
        
        // Calculate the threshold value using the step multiplier
        let threshold = minThreshold * pow(stepMultiplier, currentStep)
        
        print("DEBUG: Converting linear \(clampedLinear) to threshold:")
        print("DEBUG: - Total steps: \(totalSteps)")
        print("DEBUG: - Current step: \(currentStep)")
        print("DEBUG: - Result: \(threshold)")
        
        // Ensure output is in valid range
        return max(minThreshold, min(maxThreshold, threshold))
    }
    
    // Convert logarithmic threshold to linear slider value (0-1)
    private func logarithmicToLinear(_ threshold: Double) -> Double {
        // Ensure input is in valid range
        let clampedThreshold = max(minThreshold, min(maxThreshold, threshold))
        
        // Calculate the number of steps needed to go from min to max
        let totalSteps = log(maxThreshold / minThreshold) / log(stepMultiplier)
        
        // Calculate which step we're on
        let currentStep = log(clampedThreshold / minThreshold) / log(stepMultiplier)
        
        // Convert to linear scale
        let linear = currentStep / totalSteps
        
        print("DEBUG: Converting threshold \(clampedThreshold) to linear:")
        print("DEBUG: - Total steps: \(totalSteps)")
        print("DEBUG: - Current step: \(currentStep)")
        print("DEBUG: - Result: \(linear)")
        
        // Ensure output is in valid range
        return max(0.0, min(1.0, linear))
    }
    
    private func processKColorsUpdate() {
        guard !isProcessingKColors else {
            print("DEBUG: Already processing kColors update")
            return
        }
        
        isProcessingKColors = true
        print("DEBUG: Processing kColors update to: \(kColors)")
        
        if let image = savedImageData.flatMap(UIImage.init) {
            print("DEBUG: Starting image reprocessing with new k value")
            // Process image on background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                print("DEBUG: Beginning image processing on background thread")
                self?.bitmapAnalyzer.setK(self?.kColors ?? 8)  // Ensure k is set before processing
                self?.bitmapAnalyzer.loadImage(image)
                print("DEBUG: Image processing completed")
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    print("DEBUG: Updating UI on main thread")
                    self?.processedImage = self?.bitmapAnalyzer.getProcessedImage()
                    self?.updateScale()
                    print("DEBUG: UI update completed")
                    
                    // Check if we have a pending update
                    if let pendingUpdate = self?.pendingKColorsUpdate {
                        print("DEBUG: Processing pending update: \(pendingUpdate)")
                        self?.pendingKColorsUpdate = nil
                        self?.isProcessingKColors = false  // Reset processing flag before triggering new update
                        self?.kColors = pendingUpdate
                    } else {
                        self?.isProcessingKColors = false
                    }
                }
            }
        } else {
            print("DEBUG: No image data available for reprocessing")
            isProcessingKColors = false
        }
    }
    
    func applySettings(kColors: Int, method: ColorQuantizationMethod) {
        print("DEBUG: Applying new settings - k: \(kColors), method: \(method)")
        
        // Update settings first
        self.kColors = kColors
        self.quantizationMethod = method
        
        // Process image with new settings
        if let image = savedImageData.flatMap(UIImage.init) {
            print("DEBUG: Starting image processing with new settings")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                print("DEBUG: Beginning image processing on background thread")
                
                // Process the image
                self.bitmapAnalyzer.loadImage(image)
                
                // Update UI on main thread
                DispatchQueue.main.async {
                    print("DEBUG: Updating UI on main thread")
                    self.processedImage = self.bitmapAnalyzer.getProcessedImage()
                    self.updateScale()
                    print("DEBUG: UI update completed")
                }
            }
        } else {
            print("DEBUG: No image data available for processing")
        }
    }
} 