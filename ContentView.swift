import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var viewModel = FractalTonesViewModel()
    @State private var selectedImage: UIImage?
    @State private var isPlaying = false
    @State private var imageSelection: PhotosPickerItem?
    @State private var tempKColors: Double = 4 // Changed default to 4
    @State private var tempQuantizationMethod: ColorQuantizationMethod = .uniform // Changed default to uniform
    @State private var alertMessage: String?
    @State private var showAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image Selection
                PhotosPicker(selection: $imageSelection, matching: .images) {
                    Text("Select Image")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .onChange(of: imageSelection) { newValue in
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            selectedImage = image
                            viewModel.loadImage(image)
                        }
                    }
                }
                
                // Image Display
                if let image = selectedImage {
                    VStack {
                        Text("Original Image")
                            .font(.headline)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 150)
                        
                        if let processedImage = viewModel.processedImage {
                            Text("Processed Image")
                                .font(.headline)
                                .padding(.top)
                            Image(uiImage: processedImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 150)
                        }
                    }
                } else if let savedData = viewModel.savedImageData,
                          let savedImage = UIImage(data: savedData) {
                    VStack {
                        Text("Original Image")
                            .font(.headline)
                        Image(uiImage: savedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 150)
                        
                        if let processedImage = viewModel.processedImage {
                            Text("Processed Image")
                                .font(.headline)
                                .padding(.top)
                            Image(uiImage: processedImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 150)
                        }
                    }
                }
                
                // Settings
                VStack(spacing: 15) {
                    Text("Settings")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // K Colors Slider
                    VStack(alignment: .leading) {
                        Text("Number of Colors (k): \(Int(tempKColors))")
                            .foregroundColor(.black)
                        Slider(value: $tempKColors, in: 1...64, step: 1)
                            .accentColor(.blue)
                    }
                    
                    // Quantization Method Picker
                    Picker("Quantization Method", selection: $tempQuantizationMethod) {
                        Text("Direct").tag(ColorQuantizationMethod.direct)
                        Text("Uniform").tag(ColorQuantizationMethod.uniform)
                        Text("K-Means").tag(ColorQuantizationMethod.kMeans)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    // Apply Settings Button
                    Button(action: {
                        viewModel.applySettings(kColors: Int(tempKColors), method: tempQuantizationMethod)
                    }) {
                        Text("Apply Settings")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(15)
                
                // Movement Controls
                VStack(spacing: 15) {
                    Text("Movement Controls")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Movement Threshold Slider
                    VStack(alignment: .leading) {
                        Text("Movement Threshold: \(String(format: "%.2f", viewModel.movementThreshold)) feet")
                            .foregroundColor(.black)
                        Slider(value: $viewModel.thresholdSliderValue, in: 0...1)
                            .accentColor(.blue)
                    }
                    
                    // Play/Stop Button
                    Button(action: {
                        if isPlaying {
                            viewModel.stopPlayback()
                        } else {
                            viewModel.startPlayback()
                        }
                        isPlaying.toggle()
                    }) {
                        Text(isPlaying ? "Stop" : "Start")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isPlaying ? Color.red : Color.green)
                            .cornerRadius(10)
                    }
                    
                    // Movement Stats
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Total Distance: \(String(format: "%.2f", viewModel.totalAccumulatedDistance)) feet")
                            .foregroundColor(.black)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(15)
            }
            .padding()
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .onAppear {
            // Initialize temporary values with current settings
            tempKColors = Double(viewModel.kColors)
            tempQuantizationMethod = viewModel.quantizationMethod
            
            // Add observer for alert
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ShowAlert"),
                object: nil,
                queue: .main
            ) { notification in
                if let message = notification.userInfo?["message"] as? String {
                    alertMessage = message
                    showAlert = true
                    // Update the slider value to match the current k value
                    tempKColors = Double(viewModel.kColors)
                }
            }
        }
        .alert("Color Count Warning", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
} 