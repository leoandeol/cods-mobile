# CODS Mobile - Architecture Documentation

## Overview

CODS Mobile is a real-time object detection application built with Flutter that runs DETR (DEtection TRansformer) models on mobile devices using ExecuTorch. The app captures live video from the device camera, processes frames through a neural network, and displays detected objects with bounding boxes overlaid on the camera preview.

## Technology Stack

- **Frontend Framework**: Flutter (Dart)
- **ML Runtime**: ExecuTorch (PyTorch's mobile runtime)
- **Model**: DETR ResNet-50 (Facebook Research)
- **Camera**: Flutter Camera plugin
- **Image Processing**: Dart image package

## System Architecture

### High-Level Flow

```
Camera → Image Stream → Preprocessing → ML Model → Postprocessing → UI Rendering
   ↓           ↓              ↓            ↓             ↓              ↓
Camera     YUV420      Normalization   ExecuTorch   NMS Filter    Detection
Service    to JPEG     + Resize to     Inference    + Coord       Painter
                       640x640                      Transform
```

## Component Structure

### 1. **Models** (`lib/models/`)

Data structures representing detection objects:

#### `detection_box.dart`
- **Purpose**: Simple rectangle representation for UI rendering
- **Fields**:
  - `x, y`: Top-left corner coordinates
  - `width, height`: Box dimensions
- **Usage**: Final output sent to the painter for drawing

#### `detection_result.dart`
- **Purpose**: Complete detection information from the model
- **Fields**:
  - `x1, y1, x2, y2`: Bounding box corners (xyxy format)
  - `confidence`: Detection confidence score (0-1)
  - `classId`: COCO class identifier (1-91)
  - `classConfidence`: Class-specific confidence
- **Usage**: Intermediate representation before UI rendering

#### `coco_classes.dart`
- **Purpose**: Maps class IDs to human-readable names
- **Content**: 91 COCO dataset object classes (person, car, dog, etc.)

### 2. **Services** (`lib/services/`)

Business logic and processing engines:

#### `model_service.dart`
Core ML inference service managing the DETR model.

**Key Methods**:
- `loadModel()`: Loads the `.pte` model from assets into memory
- `prepareImageForModel()`: 
  - Resizes images to 640x640
  - Converts to RGB
  - Applies ImageNet normalization (mean/std)
  - Converts to CHW format (Channel-Height-Width)
- `runInference()`: Executes model forward pass
- `postprocess()`: Converts raw model outputs to detections
  - Box format conversion (cxcywh → xyxy)
  - Coordinate scaling (normalized → absolute)
  - Softmax on class logits
  - Confidence thresholding (>0.5)
  - NaN/infinite filtering

**Model Details**:
- **Input**: `[1, 3, 640, 640]` float32 tensor
- **Outputs**:
  1. **Logits**: `[1, 100, 92]` - class probabilities for 100 proposals
  2. **Boxes**: `[1, 100, 4]` - bounding box coordinates (cx, cy, w, h)

#### `camera_service.dart`
Manages camera lifecycle and image capture.

**Key Methods**:
- `initialize()`: Sets up camera with high resolution, YUV420 format
- `switchCamera()`: Toggles between front/back cameras
- `startImageStream()`: Begins continuous frame capture
- `convertYUV420ToImage()`: Converts camera's YUV format to JPEG bytes
  - Uses color space conversion formulas
  - Handles UV plane stride/pixel calculations

**Camera Configuration**:
- Resolution: High preset
- Format: YUV420 (efficient for video)
- Audio: Disabled
- Frame rate: Continuous stream

#### `detection_service.dart`
Orchestrates the detection pipeline.

**Workflow**:
1. Receives `CameraImage` from stream
2. Converts YUV420 → JPEG via `CameraService`
3. Preprocesses image via `ModelService`
4. Runs inference
5. Postprocesses outputs
6. Converts `DetectionResult` → `DetectionBox`
7. Validates coordinates (NaN/infinite checks)
8. Returns `DetectionResults` bundle

**Thread Safety**: Uses `_isProcessing` flag to prevent concurrent frame processing

### 3. **Painters** (`lib/painters/`)

#### `detection_painter.dart`
Custom Flutter painter that draws bounding boxes on camera preview.

**Coordinate Transformation Logic**:

The painter handles complex coordinate transformations because:
- Camera captures in landscape (wider than tall)
- Preview may be portrait (taller than wide)
- Detections are in original image space
- Must map to canvas space

**Transformation Steps**:
1. **Rotation Check**: 
   - If canvas is portrait AND image is landscape → rotate 90°
   - Transform: `(x, y) → (y, width - x)`
   - Swap width/height
   
2. **Scaling**:
   - Calculate scale factors for X and Y
   - Use minimum to maintain aspect ratio
   - Apply to coordinates and dimensions
   
3. **Centering**:
   - Calculate letterbox/pillarbox offsets
   - Center the scaled image within canvas

4. **Label Rendering**:
   - Uses `TextPainter` for class names
   - Displays confidence percentages
   - Positions above bounding box

**Debug Output**: Extensive logging for first 3 detections to aid troubleshooting

### 4. **Widgets** (`lib/widgets/`)

#### `camera_preview_widget.dart`
Reusable camera preview with detection overlay.

**Features**:
- Mirrored camera preview (`scaleX: -1` for selfie effect)
- Layered rendering (video + bounding boxes)
- Optional camera switch button
- Responsive sizing (90% width, 60% height)
- Black border for visual separation

**Rendering Layers**:
```
Stack
├── Container (border)
│   └── AspectRatio (maintains camera ratio)
│       └── Stack (video + overlay)
│           ├── Transform (mirrored preview)
│           └── CustomPaint (detections)
└── FloatingActionButton (camera switch)
```

### 5. **Screens** (`lib/screens/`)

#### `home_screen.dart`
Main application screen coordinating all services.

**State Management**:
- `_isCameraInitialized`: Controls loading spinner
- `_detections`: Current bounding boxes
- `_detectionResults`: Current detection metadata
- `_originalImageSize`: Stores frame dimensions
- `_isProcessing`: Prevents frame queue buildup

**Lifecycle**:
1. `initState()`: Initialize services
2. `loadModel()`: Load ML model (async)
3. `initializeCamera()`: Start camera
4. `startDetectionStream()`: Begin processing
5. Frame callback → `_runDetectionOnStream()`
6. `dispose()`: Clean up resources

**Demo Feature**: Counter button (inherited from Flutter template, not used for detection)

## Data Flow

### Frame Processing Pipeline

```
┌─────────────┐
│   Camera    │ 1920x1080 YUV420
└──────┬──────┘
       │
       ↓ CameraService.convertYUV420ToImage()
┌─────────────┐
│ JPEG Bytes  │ 1920x1080 RGB
└──────┬──────┘
       │
       ↓ ModelService.prepareImageForModel()
┌─────────────┐
│ Normalized  │ 640x640 Float32 (CHW, ImageNet norm)
│   Tensor    │
└──────┬──────┘
       │
       ↓ ModelService.runInference()
┌─────────────┐
│ Raw Outputs │ Logits[1,100,92] + Boxes[1,100,4]
└──────┬──────┘
       │
       ↓ ModelService.postprocess()
┌─────────────┐
│ Detections  │ DetectionResult[] (filtered, scaled)
└──────┬──────┘
       │
       ↓ DetectionService.processFrame()
┌─────────────┐
│ UI Boxes    │ DetectionBox[] (x,y,w,h in image space)
└──────┬──────┘
       │
       ↓ DetectionPainter.paint()
┌─────────────┐
│   Canvas    │ Bounding boxes on screen
└─────────────┘
```

## Model Details

### DETR (DEtection TRansformer)

**Model**: Facebook Research DETR ResNet-50  
**Export Process**: See `model_to_pte.py`

1. **PyTorch Hub**: Load pretrained DETR
2. **Export**: Convert to ONNX-like format
3. **Optimization**: XNNPACK backend for CPU inference
4. **Serialization**: Save as `.pte` (PyTorch ExecuTorch)

**Architecture**:
- **Backbone**: ResNet-50 (feature extraction)
- **Transformer**: Encoder-decoder attention
- **Heads**: 100 object proposals
  - Classification head → 92 classes (91 COCO + background)
  - Box regression head → 4 coordinates (cx, cy, w, h)

**Key Characteristics**:
- No anchor boxes (unlike YOLO/Faster R-CNN)
- Set-based loss (Hungarian matching)
- End-to-end trainable
- Outputs exactly 100 proposals (padded with background class)

### Inference Parameters

- **Input Size**: 640×640 (DETR is flexible, but 640 chosen for speed)
- **Normalization**: ImageNet stats
  - Mean: [0.485, 0.456, 0.406]
  - Std: [0.229, 0.224, 0.225]
- **Confidence Threshold**: 0.5 (filters low-confidence detections)
- **Format**: Float32, CHW order

## Coordinate Systems

### Three Coordinate Spaces

1. **Image Space** (original camera frame)
   - Origin: Top-left
   - Units: Pixels
   - Example: 1920×1080 landscape

2. **Normalized Space** (model output)
   - Origin: Top-left
   - Units: 0.0 to 1.0
   - Example: (0.5, 0.5) = center

3. **Canvas Space** (UI rendering)
   - Origin: Top-left
   - Units: Logical pixels
   - Example: May be portrait 375×812 (iPhone)

### Transformation Math

**Box Format Conversion**:
```dart
// Model outputs: (cx, cy, w, h) normalized
// Convert to corners:
x1 = cx - w/2
y1 = cy - h/2
x2 = cx + w/2
y2 = cy + h/2

// Scale to image size:
x1_abs = x1 * image_width
y1_abs = y1 * image_height
x2_abs = x2 * image_width
y2_abs = y2 * image_height
```

**Canvas Rotation** (when preview is portrait, image is landscape):
```dart
// Rotate 90° counter-clockwise:
box_x = original_y
box_y = image_width - (original_x + original_width)
box_width = original_height
box_height = original_width
```

**Scaling with Aspect Ratio**:
```dart
scale_x = canvas_width / image_width
scale_y = canvas_height / image_height
scale = min(scale_x, scale_y)  // Maintain aspect ratio

scaled_x = box_x * scale
scaled_y = box_y * scale
```

**Centering** (letterboxing/pillarboxing):
```dart
scaled_image_width = image_width * scale
scaled_image_height = image_height * scale

offset_x = (canvas_width - scaled_image_width) / 2
offset_y = (canvas_height - scaled_image_height) / 2

final_x = scaled_x + offset_x
final_y = scaled_y + offset_y
```

## Performance Considerations

### Optimization Strategies

1. **Frame Skipping**:
   - `_isProcessing` flag prevents queue buildup
   - Only one frame processed at a time
   - Drops frames if inference is slower than camera FPS

2. **YUV420 Format**:
   - Native camera format
   - More efficient than RGB for capture
   - Conversion happens once per frame

3. **XNNPACK Backend**:
   - Optimized for ARM CPUs
   - Uses NEON SIMD instructions
   - Quantization-aware (though this model uses float32)

4. **Resolution Trade-off**:
   - 640×640 chosen for balance
   - Smaller = faster but less accurate
   - Larger = slower but more detailed

### Expected Performance

- **iPhone/Android Flagship**: 15-30 FPS
- **Mid-range Devices**: 5-15 FPS
- **Low-end Devices**: 1-5 FPS

**Bottlenecks**:
1. Model inference (70-80% of time)
2. Image preprocessing (10-15%)
3. YUV conversion (5-10%)
4. UI rendering (5%)

## Error Handling

### Validation Checks

1. **Model Loading**:
   - File existence check
   - Overwrite on version change
   - Exception handling in `loadModel()`

2. **Camera Initialization**:
   - Empty camera list check
   - Disposal before re-initialization
   - Stream stop error catching

3. **Detection Validation**:
   - NaN coordinate filtering
   - Infinite value checks
   - Confidence thresholding
   - Bounds checking (0 ≤ coord ≤ image_size)

4. **UI Safety**:
   - `mounted` checks before `setState()`
   - Null-aware operators (`?.`, `??`)
   - Loading states (spinner while initializing)

### Debug Logging

Extensive print statements for troubleshooting:
- `[MODEL]`: Model loading events
- `[PREPROCESSING]`: Image transformation details
- `[INFERENCE]`: Model input/output info
- `POSTPROCESS`: Detection filtering
- `DETECTION PAINTER`: Coordinate transformations

## File Structure

```
lib/
├── main.dart                    # Original monolithic version
├── main_refactored.dart         # Clean entry point
├── utils.dart                   # Tensor utilities (unused)
├── models/
│   ├── detection_box.dart       # UI box representation
│   ├── detection_result.dart    # ML output representation
│   └── coco_classes.dart        # Class name mapping
├── services/
│   ├── model_service.dart       # ML inference engine
│   ├── camera_service.dart      # Camera management
│   └── detection_service.dart   # Pipeline orchestration
├── painters/
│   └── detection_painter.dart   # Bounding box rendering
├── widgets/
│   └── camera_preview_widget.dart  # Camera UI component
└── screens/
    └── home_screen.dart         # Main application screen

assets/
└── model.pte                    # ExecuTorch model (167MB)

model_to_pte.py                  # Model export script
```

## Dependencies

### Flutter Packages
- `camera: ^0.11.0+2` - Camera access
- `executorch_flutter: ^0.0.2` - ML runtime
- `path_provider: ^2.1.5` - File system access
- `image: ^4.x` - Image manipulation
- `cupertino_icons: ^1.0.8` - iOS icons

### Python (for model export)
- `torch` - PyTorch framework
- `torchvision` - DETR model source
- `executorch` - Export tools
- `scipy` - Dependency for DETR

## Future Improvements

### Potential Enhancements
1. **Performance**:
   - Use quantized models (int8)
   - GPU backend (CoreML for iOS, OpenGL for Android)
   - Smaller models (DETR-tiny, MobileNet-based)

2. **Features**:
   - Object tracking across frames
   - Recording with bounding boxes
   - Custom model training
   - Multiple object selection

3. **Code Quality**:
   - Unit tests for services
   - Integration tests for detection pipeline
   - Error reporting (Sentry/Firebase)
   - Performance monitoring

4. **UX**:
   - Settings screen (threshold adjustment)
   - FPS counter
   - Model switching
   - Detection history

## Troubleshooting

### Common Issues

**1. Detections not showing**:
- Check console for `[INFERENCE]` outputs
- Verify model loaded successfully
- Ensure confidence > 0.5
- Check coordinate transformation logs

**2. Boxes in wrong position**:
- Review `DETECTION PAINTER` logs
- Verify `_originalImageSize` is correct
- Check rotation logic (portrait vs landscape)
- Validate scaling calculations

**3. Low FPS**:
- Use smaller input size (e.g., 320×320)
- Skip more frames (process every Nth frame)
- Consider quantized model
- Profile with Flutter DevTools

**4. Camera not starting**:
- Check permissions (Info.plist for iOS, AndroidManifest for Android)
- Verify `cameras` list is not empty
- Ensure initialization completes before streaming

## References

- **DETR Paper**: [End-to-End Object Detection with Transformers](https://arxiv.org/abs/2005.12872)
- **ExecuTorch Docs**: [pytorch.org/executorch](https://pytorch.org/executorch)
- **COCO Dataset**: [cocodataset.org](https://cocodataset.org)
- **Flutter Camera**: [pub.dev/packages/camera](https://pub.dev/packages/camera)

---

**Last Updated**: October 2025  
**Version**: 1.0.0  
**Author**: CODS Mobile Team
