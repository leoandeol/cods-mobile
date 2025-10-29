# Code Organization Guide

## Overview

This document explains the reorganization of the CODS Mobile codebase from a monolithic structure to a modular, maintainable architecture.

## What Was Changed

### Before: Monolithic Structure
```
lib/
├── main.dart       (900+ lines - everything in one file)
└── utils.dart      (TensorHelper class - unused)
```

**Problems**:
- All code in single file (900+ lines)
- Hard to navigate and understand
- Difficult to test individual components
- No separation of concerns
- Code reuse nearly impossible

### After: Modular Structure
```
lib/
├── main_refactored.dart         (50 lines - clean entry point)
├── models/                      (Data structures)
│   ├── detection_box.dart       
│   ├── detection_result.dart    
│   └── coco_classes.dart        
├── services/                    (Business logic)
│   ├── model_service.dart       (300 lines)
│   ├── camera_service.dart      (80 lines)
│   └── detection_service.dart   (100 lines)
├── painters/                    (Rendering)
│   └── detection_painter.dart   (200 lines)
├── widgets/                     (UI components)
│   └── camera_preview_widget.dart (60 lines)
└── screens/                     (Pages)
    └── home_screen.dart         (150 lines)
```

**Benefits**:
- Clear separation of concerns
- Easy to locate specific functionality
- Testable components
- Reusable services
- Better code organization

## File-by-File Breakdown

### Entry Point

#### `main_refactored.dart` (50 lines)
**Purpose**: App initialization  
**What it does**:
- Initialize Flutter bindings
- Get available cameras
- Create MaterialApp
- Pass cameras to HomeScreen

**Key code**:
```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}
```

---

### Models (Data Structures)

#### `models/detection_box.dart` (10 lines)
**Purpose**: Simple rectangle for UI rendering  
**Why separate**: Clean data structure, reusable  
**Fields**: `x, y, width, height`

#### `models/detection_result.dart` (15 lines)
**Purpose**: Complete detection info from model  
**Why separate**: Separates ML output from UI representation  
**Fields**: `x1, y1, x2, y2, confidence, classId, classConfidence`

#### `models/coco_classes.dart` (100 lines)
**Purpose**: Object class names mapping  
**Why separate**: Large constant data, used by multiple components  
**Content**: List of 91 COCO class names

---

### Services (Business Logic)

#### `services/model_service.dart` (300 lines)
**Purpose**: ML inference engine  
**Why separate**: Complex logic, independent of UI  

**Responsibilities**:
1. Load ExecuTorch model
2. Preprocess images (resize, normalize, format conversion)
3. Run inference
4. Postprocess outputs (box conversion, scaling, filtering)
5. Mathematical operations (softmax, coordinate transforms)

**Key methods**:
- `loadModel()`: Asset loading, file management
- `prepareImageForModel()`: Image preprocessing pipeline
- `runInference()`: Model forward pass
- `postprocess()`: Output transformation and filtering
- `boxCxcywhToXyxy()`: Coordinate format conversion
- `softmaxLastDim()`: Probability calculation

**Extracted from**: 350 lines from original `main.dart`

#### `services/camera_service.dart` (80 lines)
**Purpose**: Camera lifecycle management  
**Why separate**: Encapsulates camera logic, reusable for other screens  

**Responsibilities**:
1. Initialize camera with correct settings
2. Switch between cameras
3. Start/stop image stream
4. Convert YUV420 to JPEG

**Key methods**:
- `initialize()`: Setup camera controller
- `switchCamera()`: Toggle front/back
- `startImageStream()`: Begin frame capture
- `convertYUV420ToImage()`: Color space conversion
- `dispose()`: Cleanup resources

**Extracted from**: 100 lines from original `main.dart`

#### `services/detection_service.dart` (100 lines)
**Purpose**: Orchestrate detection pipeline  
**Why separate**: Coordinates multiple services, clear workflow  

**Responsibilities**:
1. Combine camera and model services
2. Manage detection workflow
3. Validate outputs
4. Return structured results

**Key methods**:
- `processFrame()`: End-to-end detection pipeline
  - YUV conversion
  - Preprocessing
  - Inference
  - Postprocessing
  - Validation
  - Format conversion

**New component**: Created to coordinate services

---

### Painters (Rendering)

#### `painters/detection_painter.dart` (200 lines)
**Purpose**: Draw bounding boxes on canvas  
**Why separate**: Complex coordinate math, pure rendering logic  

**Responsibilities**:
1. Transform coordinates (image → canvas space)
2. Handle rotation for portrait/landscape
3. Scale with aspect ratio
4. Center with letterboxing
5. Draw boxes and labels

**Key logic**:
- Rotation detection and transformation
- Multi-space coordinate mapping
- Aspect ratio preservation
- Debug logging for troubleshooting

**Extracted from**: 150 lines from original `main.dart`

---

### Widgets (UI Components)

#### `widgets/camera_preview_widget.dart` (60 lines)
**Purpose**: Reusable camera preview with overlay  
**Why separate**: Composable UI component, can be used elsewhere  

**Responsibilities**:
1. Display camera preview
2. Apply mirror transform
3. Overlay detection painter
4. Show camera switch button

**Props**:
- `cameraController`: Camera instance
- `detections`: Boxes to draw
- `detectionResults`: Labels to show
- `originalImageSize`: For coordinate mapping
- `onSwitchCamera`: Callback
- `showSwitchButton`: Visibility flag

**Extracted from**: Widget build code in original `main.dart`

---

### Screens (Pages)

#### `screens/home_screen.dart` (150 lines)
**Purpose**: Main application screen  
**Why separate**: Top-level state management, service coordination  

**Responsibilities**:
1. Initialize all services
2. Manage application state
3. Handle lifecycle events
4. Coordinate frame processing
5. Update UI on detections

**State variables**:
- `_modelService`: ML engine
- `_cameraService`: Camera manager
- `_detectionService`: Pipeline orchestrator
- `_detections`: Current boxes
- `_detectionResults`: Current labels
- `_isProcessing`: Concurrency control

**Key methods**:
- `_initializeServices()`: Setup sequence
- `_startDetectionStream()`: Begin processing
- `_runDetectionOnStream()`: Frame callback
- `_switchCamera()`: Camera toggle
- `dispose()`: Cleanup

**Extracted from**: `_MyHomePageState` class in original `main.dart`

---

## Unchanged Files

### `main.dart` (900+ lines)
**Status**: Kept for reference  
**Purpose**: Original implementation  
**Why keep**: 
- Compare old vs new
- Reference implementation
- Backup if refactor has issues

### `utils.dart` (250 lines)
**Status**: Kept but unused  
**Purpose**: TensorHelper utility class  
**Why keep**: May be useful for future tensor operations  
**Note**: Not currently used by the app

---

## Design Principles Applied

### 1. **Separation of Concerns**
Each file has a single, clear responsibility:
- Models: Data structures only
- Services: Business logic only
- Painters: Rendering logic only
- Widgets: UI composition only
- Screens: State management only

### 2. **Dependency Injection**
Services are created and passed to components:
```dart
// HomeScreen creates services
_modelService = ModelService();
_cameraService = CameraService(cameras);
_detectionService = DetectionService(
  modelService: _modelService,
  cameraService: _cameraService,
);

// Widget receives dependencies
CameraPreviewWidget(
  cameraController: _cameraService.controller!,
  detections: _detections,
  ...
)
```

### 3. **Single Responsibility**
Each class does one thing:
- `ModelService`: ML inference only
- `CameraService`: Camera management only
- `DetectionService`: Pipeline coordination only

### 4. **Encapsulation**
Internal details hidden:
```dart
// CameraService hides controller details
class CameraService {
  CameraController? _controller;  // Private
  
  bool get isInitialized => ...;  // Public interface
  void startImageStream(...);     // Public interface
}
```

### 5. **Composability**
Components can be reused:
```dart
// CameraPreviewWidget can be used in any screen
class SettingsScreen extends StatelessWidget {
  Widget build(context) {
    return CameraPreviewWidget(...);  // Reuse
  }
}
```

---

## Migration Path

### Option 1: Switch Entry Point
```yaml
# pubspec.yaml
flutter:
  main: lib/main_refactored.dart
```

### Option 2: Rename Files
```bash
mv lib/main.dart lib/main_old.dart
mv lib/main_refactored.dart lib/main.dart
```

### Option 3: Gradual Migration
Keep both, test new version, then switch.

---

## Testing Strategy

With the new structure, components can be tested individually:

### Unit Tests
```dart
// Test model service independently
test('prepareImageForModel normalizes correctly', () {
  final service = ModelService();
  final result = service.prepareImageForModel(testImage);
  expect(result.length, 1 * 3 * 640 * 640);
});

// Test camera service independently
test('convertYUV420ToImage produces valid JPEG', () {
  final service = CameraService(cameras);
  final result = service.convertYUV420ToImage(mockImage);
  expect(result.isNotEmpty, true);
});
```

### Widget Tests
```dart
// Test camera preview widget
testWidgets('CameraPreviewWidget renders', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CameraPreviewWidget(
        cameraController: mockController,
        detections: [],
        ...
      ),
    ),
  );
  expect(find.byType(CameraPreview), findsOneWidget);
});
```

### Integration Tests
```dart
// Test full detection pipeline
test('processFrame returns valid detections', () async {
  final modelService = ModelService();
  await modelService.loadModel();
  
  final cameraService = CameraService(cameras);
  await cameraService.initialize(0);
  
  final detectionService = DetectionService(
    modelService: modelService,
    cameraService: cameraService,
  );
  
  final results = await detectionService.processFrame(testImage);
  expect(results.boxes.isNotEmpty, true);
});
```

---

## Code Metrics

### Before vs After

| Metric | Before | After |
|--------|--------|-------|
| **Files** | 1 main file | 10 organized files |
| **Largest file** | 900 lines | 300 lines |
| **Average file size** | 900 lines | 100 lines |
| **Testability** | Difficult | Easy |
| **Reusability** | Low | High |
| **Maintainability** | Poor | Good |

### Lines of Code Distribution

| Component | Lines | % of Total |
|-----------|-------|------------|
| Model Service | 300 | 33% |
| Detection Painter | 200 | 22% |
| Home Screen | 150 | 16% |
| Detection Service | 100 | 11% |
| COCO Classes | 100 | 11% |
| Camera Service | 80 | 9% |
| Camera Widget | 60 | 7% |
| Main | 50 | 5% |
| Models | 25 | 3% |
| **Total** | **900+** | **100%** |

---

## Directory Structure Rationale

### Why `models/`?
- Pure data structures
- No business logic
- Used across multiple layers
- Easy to serialize/deserialize

### Why `services/`?
- Business logic
- Stateful operations
- Can be tested independently
- Can be mocked for testing

### Why `painters/`?
- Custom rendering logic
- Extends Flutter's CustomPainter
- Separate from widget tree
- Performance-critical code

### Why `widgets/`?
- Reusable UI components
- Composable
- Accept props
- Stateless when possible

### Why `screens/`?
- Top-level pages
- Manage application state
- Coordinate services
- Handle navigation

---

## Future Improvements

### Potential Additions

1. **`lib/utils/`**
   - Image processing helpers
   - Math utilities
   - Constants

2. **`lib/config/`**
   - App configuration
   - Model parameters
   - Threshold values

3. **`lib/extensions/`**
   - Dart extensions
   - Helper methods

4. **`test/`**
   - Unit tests
   - Widget tests
   - Integration tests

5. **`lib/repositories/`**
   - Data persistence
   - Model storage
   - Settings storage

---

## Conclusion

The reorganization transforms a monolithic 900-line file into a clean, modular architecture with:

✅ **Clear structure**: Easy to navigate  
✅ **Separation of concerns**: Each file has one purpose  
✅ **Testability**: Components can be tested independently  
✅ **Reusability**: Services and widgets can be reused  
✅ **Maintainability**: Changes are localized  
✅ **Scalability**: Easy to add new features  

**No functionality was changed** - the app works exactly the same, but the code is now much easier to understand, maintain, and extend.

---

## Quick Reference

**Want to change detection logic?**  
→ `services/model_service.dart`

**Want to modify camera behavior?**  
→ `services/camera_service.dart`

**Want to adjust bounding box appearance?**  
→ `painters/detection_painter.dart`

**Want to redesign UI?**  
→ `screens/home_screen.dart` + `widgets/camera_preview_widget.dart`

**Want to add new object classes?**  
→ `models/coco_classes.dart`

**Want to change detection workflow?**  
→ `services/detection_service.dart`

---

For detailed technical documentation, see `ARCHITECTURE.md`.  
For quick start guide, see `QUICK_START.md`.
