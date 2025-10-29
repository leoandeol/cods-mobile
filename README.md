# CODS Mobile

Real-time object detection on mobile devices using DETR (DEtection TRansformer) and ExecuTorch.

## What It Does

CODS Mobile is a Flutter application that performs real-time object detection using your device's camera. It:
- Captures live video from your camera
- Processes frames through a DETR neural network
- Identifies 91 types of objects (people, cars, animals, etc.)
- Displays bounding boxes and labels in real-time

## Quick Start

### Prerequisites
- Flutter SDK (3.9.2+)
- iOS or Android device
- ~500MB free space (for model)

### Run the App
```bash
flutter pub get
flutter run
```

## Project Structure

```
lib/
├── main.dart                    # Original version (monolithic)
├── main_refactored.dart         # Refactored version (recommended)
├── models/                      # Data structures
│   ├── detection_box.dart
│   ├── detection_result.dart
│   └── coco_classes.dart
├── services/                    # Business logic
│   ├── model_service.dart       # ML inference
│   ├── camera_service.dart      # Camera management
│   └── detection_service.dart   # Detection pipeline
├── painters/                    # Rendering
│   └── detection_painter.dart
├── widgets/                     # UI components
│   └── camera_preview_widget.dart
└── screens/                     # Pages
    └── home_screen.dart
```

## Documentation

### 📚 Complete Guides

| Document | Purpose |
|----------|---------|
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | Complete technical documentation - system design, algorithms, coordinate transformations |
| **[QUICK_START.md](QUICK_START.md)** | Beginner-friendly guide - how it works, key concepts, code examples |
| **[CODE_ORGANIZATION.md](CODE_ORGANIZATION.md)** | Reorganization details - before/after, design principles, migration guide |
| **[SYSTEM_FLOW.md](SYSTEM_FLOW.md)** | Visual diagrams - flowcharts, data flow, architecture diagrams |

### 🚀 Where to Start

**New to the project?**  
→ Start with [QUICK_START.md](QUICK_START.md)

**Want technical details?**  
→ Read [ARCHITECTURE.md](ARCHITECTURE.md)

**Understanding the code reorganization?**  
→ Check [CODE_ORGANIZATION.md](CODE_ORGANIZATION.md)

**Visual learner?**  
→ See [SYSTEM_FLOW.md](SYSTEM_FLOW.md)

## Technology Stack

- **Framework**: Flutter (Dart)
- **ML Runtime**: ExecuTorch (PyTorch mobile)
- **Model**: DETR ResNet-50 (Facebook Research)
- **Dataset**: COCO (91 object classes)

## How It Works (High-Level)

```
Camera → YUV Conversion → Preprocessing → DETR Model → Postprocessing → UI
  ↓           ↓               ↓              ↓              ↓          ↓
1920x1080  JPEG bytes    640x640 tensor  100 proposals  Filter by   Draw boxes
YUV420     RGB format    normalized      logits+boxes   confidence  on screen
```

## Model Information

- **Input**: 640×640 RGB image (Float32, ImageNet normalized)
- **Output**: 
  - Logits: [1, 100, 92] - class scores for 100 object proposals
  - Boxes: [1, 100, 4] - coordinates (center_x, center_y, width, height)
- **Classes**: 91 COCO categories (person, car, dog, chair, etc.)
- **Confidence Threshold**: 0.5 (adjustable)
- **Format**: ExecuTorch (.pte) optimized with XNNPACK

## Performance

- **Expected FPS**: 5-30 depending on device
- **Latency**: 50-200ms per frame
- **Bottleneck**: Model inference (70-80% of processing time)

## Code Versions

### Original (`lib/main.dart`)
- Single 900-line file
- All code in one place
- Still functional

### Refactored (`lib/main_refactored.dart`)
- Modular architecture
- 10 organized files
- Testable components
- **Recommended for development**

Both versions work identically - the refactored version is just better organized.

## Key Features

✅ Real-time object detection  
✅ 91 COCO object classes  
✅ Bounding box visualization  
✅ Confidence scores  
✅ Front/back camera switching  
✅ Portrait/landscape support  
✅ Automatic coordinate transformation  

## Common Tasks

### Change Confidence Threshold
Edit `lib/services/model_service.dart`:
```dart
const confidenceThreshold = 0.3;  // Lower = more detections
```

### Modify Bounding Box Style
Edit `lib/painters/detection_painter.dart`:
```dart
final paint = Paint()
  ..color = Colors.blue  // Change color
  ..strokeWidth = 5.0;   // Change thickness
```

### Add New Features
See [CODE_ORGANIZATION.md](CODE_ORGANIZATION.md) for guidance on where to add code.

## Troubleshooting

**No detections showing?**
- Check console for logs starting with `[INFERENCE]`
- Lower confidence threshold
- Ensure model.pte is in assets/

**Boxes in wrong position?**
- Review coordinate transformation logs
- Check device orientation
- See [ARCHITECTURE.md](ARCHITECTURE.md#coordinate-systems)

**Low FPS?**
- Use smaller input size (320×320)
- Process every Nth frame
- Consider quantized model

## Development

### Project Files
- `model_to_pte.py` - Convert PyTorch DETR to ExecuTorch format
- `pubspec.yaml` - Dependencies and asset configuration
- `assets/model.pte` - Compiled model (167MB)

### Dependencies
```yaml
dependencies:
  flutter: sdk
  camera: ^0.11.0+2
  executorch_flutter: ^0.0.2
  path_provider: ^2.1.5
  image: ^4.x
```

## Future Enhancements

- [ ] Quantized models (int8) for faster inference
- [ ] GPU backend support (CoreML/OpenGL)
- [ ] Object tracking across frames
- [ ] Recording with bounding boxes
- [ ] Settings UI for threshold adjustment
- [ ] Custom model training

## References

- **DETR Paper**: [End-to-End Object Detection with Transformers](https://arxiv.org/abs/2005.12872)
- **ExecuTorch**: [pytorch.org/executorch](https://pytorch.org/executorch)
- **COCO Dataset**: [cocodataset.org](https://cocodataset.org)

## License

See [LICENSE](LICENSE) file.

---

**Documentation Map**:
- 📖 **[ARCHITECTURE.md](ARCHITECTURE.md)** - Deep technical dive
- 🚀 **[QUICK_START.md](QUICK_START.md)** - Beginner-friendly guide
- 🗂️ **[CODE_ORGANIZATION.md](CODE_ORGANIZATION.md)** - Code structure details
- 📊 **[SYSTEM_FLOW.md](SYSTEM_FLOW.md)** - Visual diagrams

**Last Updated**: October 2025
