import UIKit

enum ColorQuantizationMethod {
    case kMeans
    case uniform
    case direct
}

struct ColorComponent: Equatable, Hashable {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    
    static func == (lhs: ColorComponent, rhs: ColorComponent) -> Bool {
        return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(r)
        hasher.combine(g)
        hasher.combine(b)
    }
}

class BitmapAnalyzer {
    private var colorToToneMap: [ColorComponent: Int] = [:]
    private var currentPixelIndex = 0
    private var pixels: [UIColor] = []
    private var originalImageData: (rawData: [UInt8], width: Int, height: Int, bytesPerPixel: Int)? // Store original image data
    private var k: Int = 4 // Default number of colors
    private var quantizationMethod: ColorQuantizationMethod = .uniform
    private var uniqueColorCount: Int = 0
    private var quantizedColors: [UIColor] = []
    private let processingQueue = DispatchQueue(label: "com.fractaltones.imageprocessing", qos: .userInitiated)
    private var isProcessing = false
    
    // Maximum number of pixels to process for performance
    private let maxPixelsToProcess = 10000
    
    init() {
        // Initialize with default values
        k = 4  // Changed from 8 to 4
        quantizationMethod = .uniform  // Changed from .direct to .uniform
        print("DEBUG: BitmapAnalyzer initialized with k=\(k), method=\(quantizationMethod)")
    }
    
    func setK(_ newK: Int) {
        print("DEBUG: Setting k from \(k) to \(newK)")
        processingQueue.sync {
            k = max(1, min(newK, 256)) // Limit K between 1 and 256
            
            // If we have pixels, rebuild the color mappings
            if !pixels.isEmpty {
                print("DEBUG: Rebuilding color mappings with new k value")
                rebuildColorMappings()
            }
        }
    }
    
    private func rebuildColorMappings() {
        print("DEBUG: Starting color quantization with method: \(quantizationMethod), k=\(k)")
        
        // Safety check for original image data
        guard let imageData = originalImageData else {
            print("DEBUG: Warning - no original image data available")
            return
        }
        
        // Extract unique colors from original image data
        var uniqueColors: Set<UIColor> = []
        let sampleStep = max(1, Int(sqrt(Double(imageData.width * imageData.height) / Double(maxPixelsToProcess))))
        print("DEBUG: Grid sample step: \(sampleStep)")
        
        var samples = 0
        for y in stride(from: 0, to: imageData.height, by: sampleStep) {
            for x in stride(from: 0, to: imageData.width, by: sampleStep) {
                let offset = (y * imageData.width * imageData.bytesPerPixel) + (x * imageData.bytesPerPixel)
                guard offset + 3 < imageData.rawData.count else { continue }
                
                let red = CGFloat(imageData.rawData[offset]) / 255.0
                let green = CGFloat(imageData.rawData[offset + 1]) / 255.0
                let blue = CGFloat(imageData.rawData[offset + 2]) / 255.0
                let alpha = CGFloat(imageData.rawData[offset + 3]) / 255.0
                
                let color = UIColor(red: red, green: green, blue: blue, alpha: alpha)
                uniqueColors.insert(color)
                samples += 1
                
                if samples % 1000 == 0 {
                    print("DEBUG: Sampled \(samples) pixels")
                }
            }
        }
        print("DEBUG: Completed grid sampling with \(samples) samples")
        
        // Store the unique color count
        uniqueColorCount = uniqueColors.count
        print("DEBUG: Found \(uniqueColorCount) unique colors")
        
        // Convert to array for processing
        let uniqueColorsArray = Array(uniqueColors)
        print("DEBUG: Converting \(uniqueColorsArray.count) unique colors to array")
        
        // Perform color quantization
        var newQuantizedColors: [UIColor]
        switch quantizationMethod {
        case .kMeans:
            print("DEBUG: Using k-means clustering")
            newQuantizedColors = kMeansClustering(colors: uniqueColorsArray, k: k)
        case .uniform:
            print("DEBUG: Using uniform quantization")
            newQuantizedColors = uniformColorQuantization(colors: uniqueColorsArray, k: k)
        case .direct:
            print("DEBUG: Using direct mapping")
            newQuantizedColors = directColorMapping(colors: uniqueColorsArray)
        }
        
        // Safety check for empty quantized colors
        guard !newQuantizedColors.isEmpty else {
            print("DEBUG: Warning - no quantized colors generated")
            return
        }
        
        print("DEBUG: Generated \(newQuantizedColors.count) quantized colors")
        
        // Create mapping from original colors to quantized colors
        print("DEBUG: Creating color mapping")
        var newColorToToneMap: [ColorComponent: Int] = [:]
        
        // First, map the quantized colors to their indices
        for (index, color) in newQuantizedColors.enumerated() {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
                let component = ColorComponent(r: r, g: g, b: b)
                newColorToToneMap[component] = index
                print("DEBUG: Mapped quantized color \(index) to component: r=\(r), g=\(g), b=\(b)")
            }
        }
        
        // Update the color mapping atomically
        colorToToneMap = newColorToToneMap
        quantizedColors = newQuantizedColors
        
        // Update pixels to use quantized colors
        print("DEBUG: Starting pixel update with \(samples) pixels")
        pixels.removeAll()
        pixels.reserveCapacity(samples)
        
        for y in stride(from: 0, to: imageData.height, by: sampleStep) {
            for x in stride(from: 0, to: imageData.width, by: sampleStep) {
                let offset = (y * imageData.width * imageData.bytesPerPixel) + (x * imageData.bytesPerPixel)
                guard offset + 3 < imageData.rawData.count else { continue }
                
                let red = CGFloat(imageData.rawData[offset]) / 255.0
                let green = CGFloat(imageData.rawData[offset + 1]) / 255.0
                let blue = CGFloat(imageData.rawData[offset + 2]) / 255.0
                let alpha = CGFloat(imageData.rawData[offset + 3]) / 255.0
                
                let originalColor = UIColor(red: red, green: green, blue: blue, alpha: alpha)
                let component = ColorComponent(r: red, g: green, b: blue)
                
                if let index = colorToToneMap[component] {
                    pixels.append(quantizedColors[index])
                } else {
                    // Find nearest color
                    var minDistance = CGFloat.infinity
                    var nearestColor = quantizedColors[0]
                    
                    for quantizedColor in quantizedColors {
                        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
                        guard quantizedColor.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { continue }
                        
                        let distance = pow(red - r2, 2) + pow(green - g2, 2) + pow(blue - b2, 2)
                        if distance < minDistance {
                            minDistance = distance
                            nearestColor = quantizedColor
                        }
                    }
                    
                    pixels.append(nearestColor)
                }
            }
        }
        
        print("DEBUG: Finished updating pixels")
    }
    
    func setQuantizationMethod(_ method: ColorQuantizationMethod) {
        print("DEBUG: Setting quantization method to: \(method)")
        processingQueue.sync {
            quantizationMethod = method
            // If we have pixels, rebuild the color mappings
            if !pixels.isEmpty {
                print("DEBUG: Rebuilding color mappings with new method")
                rebuildColorMappings()
            }
        }
    }
    
    func getUniqueColorCount() -> Int {
        return uniqueColorCount
    }
    
    private func directColorMapping(colors: [UIColor]) -> [UIColor] {
        // For direct mapping, we can use a more efficient approach
        // since we don't need to sort all colors, just get unique ones
        var uniqueColors = Set<UIColor>()
        for color in colors {
            uniqueColors.insert(color)
        }
        
        // Convert to array and sort by hue
        return Array(uniqueColors).sorted { color1, color2 in
            var h1: CGFloat = 0, s1: CGFloat = 0, v1: CGFloat = 0, a1: CGFloat = 0
            var h2: CGFloat = 0, s2: CGFloat = 0, v2: CGFloat = 0, a2: CGFloat = 0
            
            color1.getHue(&h1, saturation: &s1, brightness: &v1, alpha: &a1)
            color2.getHue(&h2, saturation: &s2, brightness: &v2, alpha: &a2)
            
            return h1 < h2
        }
    }
    
    private func uniformColorQuantization(colors: [UIColor], k: Int) -> [UIColor] {
        print("DEBUG: Starting uniform quantization with \(colors.count) colors, k=\(k)")
        
        // If we have fewer colors than k, notify and adjust k
        if colors.count < k {
            print("DEBUG: Warning - image only has \(colors.count) unique colors, adjusting k from \(k) to \(colors.count)")
            // Notify the user through a notification
            NotificationCenter.default.post(
                name: NSNotification.Name("ColorCountWarning"),
                object: nil,
                userInfo: [
                    "requestedK": k,
                    "actualK": colors.count,
                    "message": "Image only has \(colors.count) unique colors. Adjusting k from \(k) to \(colors.count)."
                ]
            )
            return colors
        }
        
        // Convert colors to RGB components
        print("DEBUG: Converting colors to RGB components")
        let rgbColors = colors.map { color -> (r: Double, g: Double, b: Double) in
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: nil)
            return (Double(r), Double(g), Double(b))
        }
        
        // Find min/max values for each component
        print("DEBUG: Finding min/max values")
        let minR = rgbColors.map { $0.r }.min() ?? 0
        let maxR = rgbColors.map { $0.r }.max() ?? 1
        let minG = rgbColors.map { $0.g }.min() ?? 0
        let maxG = rgbColors.map { $0.g }.max() ?? 1
        let minB = rgbColors.map { $0.b }.min() ?? 0
        let maxB = rgbColors.map { $0.b }.max() ?? 1
        
        // Calculate step sizes for each component
        let stepSizeR = (maxR - minR) / Double(k - 1)
        let stepSizeG = (maxG - minG) / Double(k - 1)
        let stepSizeB = (maxB - minB) / Double(k - 1)
        
        // Generate k colors by interpolating between min and max values
        var quantizedColors: [UIColor] = []
        for i in 0..<k {
            let r = minR + (stepSizeR * Double(i))
            let g = minG + (stepSizeG * Double(i))
            let b = minB + (stepSizeB * Double(i))
            
            let color = UIColor(
                red: CGFloat(r),
                green: CGFloat(g),
                blue: CGFloat(b),
                alpha: 1.0
            )
            quantizedColors.append(color)
        }
        
        print("DEBUG: Generated \(quantizedColors.count) quantized colors")
        return quantizedColors
    }
    
    private func kMeansClustering(colors: [UIColor], k: Int) -> [UIColor] {
        // Convert colors to RGB components
        let colorComponents: [ColorComponent] = colors.map { color in
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return ColorComponent(r: r, g: g, b: b)
        }
        
        // Initialize centroids using a more robust method
        var centroids: [ColorComponent] = []
        
        if colorComponents.count <= k {
            // If we have fewer colors than k, use all colors and duplicate as needed
            centroids = colorComponents
            while centroids.count < k {
                centroids.append(centroids[centroids.count % centroids.count])
            }
        } else {
            // If we have more colors than k, use a more distributed sampling
            let step = colorComponents.count / k
            for i in 0..<k {
                let index = min(i * step, colorComponents.count - 1)
                centroids.append(colorComponents[index])
            }
        }
        
        var oldCentroids: [ColorComponent] = []
        var iterations = 0
        let maxIterations = 50 // Reduced from 100 for better performance
        
        // K-means iteration
        while !centroids.elementsEqual(oldCentroids) && iterations < maxIterations {
            oldCentroids = centroids
            
            // Assign colors to nearest centroid
            var clusters: [[ColorComponent]] = Array(repeating: [], count: k)
            
            for color in colorComponents {
                var minDistance = CGFloat.infinity
                var nearestCentroid = 0
                
                for (i, centroid) in centroids.enumerated() {
                    let distance = pow(color.r - centroid.r, 2) +
                                 pow(color.g - centroid.g, 2) +
                                 pow(color.b - centroid.b, 2)
                    if distance < minDistance {
                        minDistance = distance
                        nearestCentroid = i
                    }
                }
                
                clusters[nearestCentroid].append(color)
            }
            
            // Update centroids
            for i in 0..<k {
                if !clusters[i].isEmpty {
                    let cluster = clusters[i]
                    let r = cluster.map { $0.r }.reduce(0, +) / CGFloat(cluster.count)
                    let g = cluster.map { $0.g }.reduce(0, +) / CGFloat(cluster.count)
                    let b = cluster.map { $0.b }.reduce(0, +) / CGFloat(cluster.count)
                    centroids[i] = ColorComponent(r: r, g: g, b: b)
                }
            }
            
            iterations += 1
        }
        
        // Convert centroids back to UIColor
        return centroids.map { UIColor(red: $0.r, green: $0.g, blue: $0.b, alpha: 1.0) }
    }
    
    func loadImage(_ image: UIImage) {
        print("DEBUG: Starting image load")
        
        // Prevent concurrent processing
        guard !isProcessing else {
            print("DEBUG: Image processing already in progress")
            return
        }
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isProcessing = true
            defer { self.isProcessing = false }
            
            do {
                guard let cgImage = image.cgImage else {
                    print("DEBUG: Failed to get CGImage")
                    return
                }
                
                print("DEBUG: Image dimensions - width: \(cgImage.width), height: \(cgImage.height)")
                let width = cgImage.width
                let height = cgImage.height
                let bytesPerPixel = 4
                let bytesPerRow = width * bytesPerPixel
                let bitsPerComponent = 8
                
                // Calculate scaling factor to limit number of pixels
                let totalPixels = width * height
                let scaleFactor = totalPixels > self.maxPixelsToProcess ? sqrt(Double(self.maxPixelsToProcess) / Double(totalPixels)) : 1.0
                let scaledWidth = Int(Double(width) * scaleFactor)
                let scaledHeight = Int(Double(height) * scaleFactor)
                
                print("DEBUG: Scaled dimensions - width: \(scaledWidth), height: \(scaledHeight)")
                print("DEBUG: Scale factor: \(scaleFactor)")
                
                // Safety check for valid dimensions
                guard scaledWidth > 0 && scaledHeight > 0 else {
                    print("DEBUG: Invalid scaled dimensions")
                    return
                }
                
                // Clear existing data
                self.pixels.removeAll()
                self.colorToToneMap.removeAll()
                self.quantizedColors.removeAll()
                
                var rawData = [UInt8](repeating: 0, count: scaledWidth * scaledHeight * bytesPerPixel)
                
                guard let context = CGContext(
                    data: &rawData,
                    width: scaledWidth,
                    height: scaledHeight,
                    bitsPerComponent: bitsPerComponent,
                    bytesPerRow: scaledWidth * bytesPerPixel,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    print("DEBUG: Failed to create CGContext")
                    return
                }
                
                print("DEBUG: Drawing scaled image")
                // Draw scaled image
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
                
                // Store the original image data
                self.originalImageData = (rawData: rawData, width: scaledWidth, height: scaledHeight, bytesPerPixel: bytesPerPixel)
                
                // Process the image with current settings
                self.rebuildColorMappings()
                
            } catch {
                print("DEBUG: Error during image processing: \(error)")
            }
        }
    }
    
    func getNextToneIndex() -> Int {
        var result = 0
        processingQueue.sync {
            guard !pixels.isEmpty else {
                print("DEBUG: No pixels available")
                return
            }
            
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            pixels[currentPixelIndex].getRed(&r, green: &g, blue: &b, alpha: &a)
            let component = ColorComponent(r: r, g: g, b: b)
            print("DEBUG: Getting tone index for color: r=\(r), g=\(g), b=\(b)")
            
            // If we can't find the color in the map, find the closest one
            if let index = colorToToneMap[component] {
                print("DEBUG: Found exact match at index \(index)")
                currentPixelIndex = (currentPixelIndex + 1) % pixels.count
                result = index
                return
            }
            
            print("DEBUG: No exact match found, finding closest color")
            // Find the closest color
            var minDistance = CGFloat.infinity
            var nearestIndex = 0
            
            for (index, color) in quantizedColors.enumerated() {
                var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
                color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
                
                let distance = pow(r - r2, 2) + pow(g - g2, 2) + pow(b - b2, 2)
                if distance < minDistance {
                    minDistance = distance
                    nearestIndex = index
                }
            }
            
            // Update the map with the nearest color
            colorToToneMap[component] = nearestIndex
            print("DEBUG: Using nearest color at index \(nearestIndex)")
            currentPixelIndex = (currentPixelIndex + 1) % pixels.count
            result = nearestIndex
        }
        return result
    }
    
    func reset() {
        processingQueue.sync {
            currentPixelIndex = 0
        }
    }
    
    func getProcessedImage() -> UIImage? {
        var result: UIImage?
        processingQueue.sync {
            guard !pixels.isEmpty else { return }
            
            // Create a new image with the quantized colors
            let width = Int(sqrt(Double(pixels.count)))
            let height = width // Make it square for simplicity
            
            let size = CGSize(width: width, height: height)
            UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
            guard let context = UIGraphicsGetCurrentContext() else { return }
            
            // Draw the quantized pixels
            for (index, color) in pixels.enumerated() {
                let x = index % width
                let y = index / width
                let rect = CGRect(x: x, y: y, width: 1, height: 1)
                context.setFillColor(color.cgColor)
                context.fill(rect)
            }
            
            result = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
        }
        return result
    }
} 