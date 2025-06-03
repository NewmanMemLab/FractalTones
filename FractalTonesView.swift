import SwiftUI

struct FractalTonesView: View {
    @StateObject private var viewModel = FractalTonesViewModel()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                // Movement Threshold Slider
                VStack(alignment: .leading) {
                    Text("Movement Threshold: \(String(format: "%.2f", viewModel.movementThreshold)) feet")
                        .foregroundColor(.white)
                    Slider(value: $viewModel.thresholdSliderValue, in: 0...1)
                        .accentColor(.blue)
                    Text("Slider Value: \(String(format: "%.3f", viewModel.thresholdSliderValue))")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .padding(.horizontal)
                
                // Add other UI elements here
            }
        }
    }
}

#Preview {
    FractalTonesView()
} 