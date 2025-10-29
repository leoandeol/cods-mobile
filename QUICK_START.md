# CODS Mobile - Quick Start Guide

## What This App Does

CODS Mobile performs **real-time object detection** on your mobile device camera feed. It:
1. Captures live video from your camera
2. Processes each frame through a DETR neural network
3. Identifies objects (people, cars, animals, etc.)
4. Draws bounding boxes around detected objects
5. Shows class names and confidence scores

## Project Structure

### New Organized Structure (Recommended)

```
lib/
├── main_refactored.dart         ← Use this as entry point
├── models/                      ← Data structures
│   ├── detection_box.dart       → UI rectangle (x, y, w, h)
│   ├── detection_result.dart    → ML output (coords + confidence)
│   └── coco_classes.dart        → Object class names (91 types)
├── services/                    ← Business logic
│   ├── model_service.dart       → ML inference (DETR model)
│   ├── camera_service.dart      → Camera management
│   └── detection_service.dart   → Detection pipeline
├── painters/                    ← Rendering
│   └── detection_painter.dart   → Draws bounding boxes
├── widgets/                     ← UI components
│   └── camera_preview_widget.dart → Camera + overlay
└── screens/                     ← Pages
    └── home_screen.dart         → Main screen

lib/main.dart                    ← Original monolithic version (still works)
```

### Key Files

| File | Purpose |
|------|---------|
| `main_refactored.dart` | Clean app entry point |
| `model_service.dart` | Handles ML model, preprocessing, postprocessing |
| `camera_service.dart` | Manages camera lifecycle, YUV conversion |
| `detection_service.dart` | Orchestrates detection pipeline |
| `detection_painter.dart` | Draws boxes with coordinate transformations |
| `home_screen.dart` | Main UI, state management |

## How It Works (Simplified)

### 1. **Initialization** (App Start)
```
main() 
  → Load available cameras
  → Create app
  → Initialize ModelService (load model.pte)
  → Initialize CameraService (start camera)
  → Start image stream
```

### 2. **Detection Loop** (Every Frame)
```
Camera captures frame (YUV420 format)
  ↓
Convert YUV → JPEG
  ↓
Resize to 640×640 + normalize
  ↓
Run through DETR model
  ↓
Get 100 proposals (boxes + classes)
  ↓
Filter by confidence > 0.5
  ↓
Transform coordinates for screen
  ↓
Draw bounding boxes
```

### 3. **Model Processing**

**Input**: 
- 640×640 RGB image
- Normalized with ImageNet stats
- Float32 tensor format

**Output**:
- **Logits**: `[1, 100, 92]` - class scores for 100 boxes
- **Boxes**: `[1, 100, 4]` - coordinates (center_x, center_y, width, height)

**Postprocessing**:
1. Convert box format: `(cx, cy, w, h)` → `(x1, y1, x2, y2)`
2. Scale coordinates: normalized → absolute pixels
3. Apply softmax to class scores
4. Filter low confidence detections
5. Remove invalid coordinates (NaN/infinite)

## Code Flow Example

### When Camera Captures a Frame:

```dart
// 1. Camera triggers callback
_cameraService.startImageStream((CameraImage image) {
  _runDetectionOnStream(image);
});

// 2. Detection service processes frame
Future<void> _runDetectionOnStream(CameraImage image) async {
  if (_isProcessing) return;  // Skip if busy
  
  _isProcessing = true;
  
  // 3. Run detection pipeline
  final results = await _detectionService.processFrame(image);
  
  // 4. Update UI
  setState(() {
    _detections = results.boxes;           // For drawing
    _detectionResults = results.results;   // For labels
    _originalImageSize = Size(...);        // For coordinate mapping
  });
  
  _isProcessing = false;
}
```

### Inside Detection Pipeline:

```dart
// DetectionService.processFrame()
Future<DetectionResults> processFrame(CameraImage image) async {
  // Step 1: Convert camera format
  Uint8List imageBytes = cameraService.convertYUV420ToImage(image);
  
  // Step 2: Preprocess for model
  Float32List processedImage = modelService.prepareImageForModel(imageBytes);
  
  // Step 3: Run inference
  List<TensorData> outputs = await modelService.runInference(processedImage);
  
  // Step 4: Postprocess outputs
  List<DetectionResult> detections = modelService.postprocess(
    outputs[0],  // logits
    outputs[1],  // boxes
    image.width,
    image.height,
  );
  
  // Step 5: Convert to UI format
  List<DetectionBox> boxes = detections.map((det) => 
    DetectionBox(
      x: det.x1,
      y: det.y1,
      width: det.x2 - det.x1,
      height: det.y2 - det.y1,
    )
  ).toList();
  
  return DetectionResults(boxes, detections, ...);
}
```

## Key Concepts

### 1. **Coordinate Systems**

Three different coordinate spaces to handle:

**Image Space** (where detections happen):
- Original camera resolution (e.g., 1920×1080)
- Landscape orientation
- Absolute pixel coordinates

**Normalized Space** (model outputs):
- 0.0 to 1.0 range
- Must scale by image dimensions

**Canvas Space** (UI rendering):
- Screen dimensions (e.g., 375×812 for iPhone)
- May be portrait orientation
- Needs rotation + scaling + centering

### 2. **Box Format Conversion**

DETR outputs center-width format, but UI needs corner format:

```dart
// Model output: center format
cx = 0.5  // center X (normalized)
cy = 0.5  // center Y
w = 0.3   // width
h = 0.4   // height

// Convert to corners:
x1 = cx - w/2 = 0.35
y1 = cy - h/2 = 0.3
x2 = cx + w/2 = 0.65
y2 = cy + h/2 = 0.7

// Scale to image size (1920×1080):
x1_abs = 0.35 * 1920 = 672
y1_abs = 0.3 * 1080 = 324
x2_abs = 0.65 * 1920 = 1248
y2_abs = 0.7 * 1080 = 756
```

### 3. **Rotation Handling**

When preview is portrait but image is landscape:

```dart
// Original box in landscape image
x = 100, y = 50, w = 200, h = 150

// Rotate 90° counter-clockwise
new_x = y = 50
new_y = image_width - (x + w) = 1920 - 300 = 1620
new_w = h = 150
new_h = w = 200
```

### 4. **Frame Skipping**

To prevent queue buildup:

```dart
bool _isProcessing = false;

void onNewFrame(image) {
  if (_isProcessing) return;  // Drop frame if busy
  
  _isProcessing = true;
  await processFrame(image);
  _isProcessing = false;
}
```

## Performance Tips

### Current Implementation
- Processes frames one at a time
- Drops frames if inference is too slow
- Expected: 5-30 FPS depending on device

### Bottlenecks
1. **Model Inference** (70-80% of time)
   - DETR is heavy (ResNet-50 backbone)
   - 640×640 input size
   
2. **Image Preprocessing** (10-15%)
   - YUV conversion
   - Resizing
   - Normalization

3. **Rendering** (5-10%)
   - Drawing boxes
   - Text labels

### Optimization Ideas
- Use smaller model (DETR-tiny, MobileNet)
- Reduce input size (320×320)
- Quantize to int8
- Use GPU backend (CoreML/OpenGL)
- Process every Nth frame

## Debugging

### Enable Verbose Logging

All services already print debug info. Look for:

```
[MODEL] Loading model from: ...
[PREPROCESSING] Original image: 1920x1080
[INFERENCE] Calling model.forward() with input shape: [1, 3, 640, 640]
POSTPROCESS START
########## DETECTION PAINTER ##########
```

### Common Checks

**No detections showing?**
```
1. Check console for "Filtered to X valid detections"
2. Verify X > 0
3. If X = 0, lower confidence threshold in model_service.dart:
   const confidenceThreshold = 0.3;  // was 0.5
```

**Boxes in wrong place?**
```
1. Look for "DETECTION PAINTER" logs
2. Check "Canvas size" vs "Original image size"
3. Verify "Needs rotation" matches your device orientation
4. Compare "FINAL canvas box" coordinates
```

**App crashes on start?**
```
1. Check model.pte exists in assets/
2. Verify camera permissions in platform configs
3. Check Flutter version compatibility
```

## Model Information

### DETR (DEtection TRansformer)
- **Source**: Facebook Research
- **Backbone**: ResNet-50
- **Training**: COCO dataset (91 classes)
- **Format**: ExecuTorch (.pte)
- **Size**: ~167 MB
- **Backend**: XNNPACK (CPU optimized)

### Detectable Objects (COCO Classes)
Person, bicycle, car, motorcycle, airplane, bus, train, truck, boat, traffic light, fire hydrant, stop sign, parking meter, bench, bird, cat, dog, horse, sheep, cow, elephant, bear, zebra, giraffe, backpack, umbrella, handbag, tie, suitcase, frisbee, skis, snowboard, sports ball, kite, baseball bat, baseball glove, skateboard, surfboard, tennis racket, bottle, wine glass, cup, fork, knife, spoon, bowl, banana, apple, sandwich, orange, broccoli, carrot, hot dog, pizza, donut, cake, chair, couch, potted plant, bed, dining table, toilet, TV, laptop, mouse, remote, keyboard, cell phone, microwave, oven, toaster, sink, refrigerator, book, clock, vase, scissors, teddy bear, hair drier, toothbrush

## Next Steps

1. **Run the refactored version**:
   - Change `pubspec.yaml` main to `lib/main_refactored.dart`
   - Or rename `main_refactored.dart` to `main.dart`

2. **Customize**:
   - Adjust confidence threshold in `model_service.dart`
   - Change colors in `detection_painter.dart`
   - Modify UI layout in `home_screen.dart`

3. **Extend**:
   - Add object tracking
   - Implement recording
   - Try different models
   - Add settings screen

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    HomeScreen                           │
│  (State Management + UI Layout)                         │
└────┬────────────────────────────────────────────────────┘
     │
     ├─► ModelService ──────► ExecuTorch Runtime
     │    (ML Inference)       └─► model.pte (DETR)
     │
     ├─► CameraService ───────► Flutter Camera Plugin
     │    (Video Capture)       └─► Device Camera
     │
     └─► DetectionService ────► Pipeline Orchestrator
          │
          ├─► processFrame()
          │    ├─ YUV → JPEG
          │    ├─ Preprocess
          │    ├─ Inference
          │    ├─ Postprocess
          │    └─ Validate
          │
          └─► DetectionResults
               └─► CameraPreviewWidget
                    └─► DetectionPainter (draws boxes)
```

## References

- Full documentation: `ARCHITECTURE.md`
- Model export: `model_to_pte.py`
- Original code: `lib/main.dart`
- Refactored code: `lib/main_refactored.dart`

---

**Pro Tip**: Start by reading `ARCHITECTURE.md` for complete system details, then dive into specific service files for implementation details.
