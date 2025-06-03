# FractalTones

FractalTones is an iOS application that transforms images into musical compositions through movement. The app analyzes the colors in an image and maps them to musical tones, creating a unique sonic experience as you move your device.

## Features

- **Image Analysis**: Upload any image to analyze its color composition
- **Color Quantization**: Choose between uniform or direct color quantization methods
- **Movement-Based Playback**: Generate tones based on device movement
- **Customizable Threshold**: Adjust the movement sensitivity to control tone frequency
- **Background Operation**: Continue playing tones even when the device is locked
- **Real-time Processing**: Instant feedback as you move your device

## Requirements

- iOS 15.0+
- Xcode 13.0+
- Swift 5.5+
- Physical iOS device (CoreMotion features require actual device movement)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/NewmanMemLab/FractalTones.git
```

2. Open the project in Xcode:
```bash
cd FractalTones
open FractalTones.xcodeproj
```

3. Build and run the project on your iOS device (not simulator)

## Usage

1. Launch the app
2. Select an image from your photo library
3. Choose your preferred color quantization method:
   - Uniform: Divides the color space into equal segments
   - Direct: Maps each unique color to a tone
4. Adjust the movement threshold using the slider
5. Start playback and move your device to generate tones
6. The app will continue playing tones even when the device is locked

## How It Works

### Color Analysis
The app uses a custom `BitmapAnalyzer` class to process images and extract color information. It supports two quantization methods:
- **Uniform Quantization**: Divides the RGB color space into equal segments, creating a more structured musical output
- **Direct Mapping**: Maps each unique color in the image to a specific tone, preserving the image's color diversity

### Movement Detection
FractalTones uses CoreMotion to detect device movement:
- Accelerometer data is processed to calculate movement velocity
- Movement is converted to feet for intuitive distance tracking
- A configurable threshold determines when new tones are triggered

### Audio Generation
The app generates tones using the following process:
- Colors are mapped to frequencies in an E-flat scale
- Tones are generated using sine wave synthesis
- Audio playback continues in the background
- Multiple tones can be played simultaneously

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Disclaimer

This code is provided "as is" without warranty of any kind, either express or implied, including but not limited to the implied warranties of merchantability and fitness for a particular purpose. The entire risk as to the quality and performance of the code is with you.

This code was generated with assistance from Claude 3.7 Sonnet, an AI language model developed by Anthropic. While the AI helped in the development process, the final implementation and any errors are the responsibility of a deeply complex back and forth between a creative but technically challenged researcher and a chatbot who just did what it was asked and many things it wasn't asked.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- CoreMotion framework for movement detection
- AVFoundation for audio processing
- SwiftUI for the user interface

## Contact

NewmanMemLab - [@NewmanMemLab](https://memlab.sitehost.iu.edu/)

Project Link: [https://github.com/NewmanMemLab/FractalTones](https://github.com/NewmanMemLab/FractalTones) 