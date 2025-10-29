# CODS Mobile - System Flow Diagrams

## 1. Application Startup Flow

```
┌─────────────────────────────────────────────────────────────┐
│                         main()                              │
│                                                             │
│  1. WidgetsFlutterBinding.ensureInitialized()              │
│  2. cameras = await availableCameras()                     │
│  3. runApp(MyApp())                                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                      MyApp Widget                           │
│                                                             │
│  - Creates MaterialApp                                     │
│  - Sets theme                                              │
│  - Creates HomeScreen with cameras                         │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  HomeScreen.initState()                     │
│                                                             │
│  _initializeServices()                                     │
│    ├─► _modelService = ModelService()                     │
│    │     └─► loadModel() [Load model.pte from assets]     │
│    │                                                        │
│    ├─► _cameraService = CameraService(cameras)            │
│    │     └─► initialize() [Setup camera controller]       │
│    │                                                        │
│    └─► _detectionService = DetectionService(...)          │
│          └─► [Combines model + camera services]           │
│                                                             │
│  _startDetectionStream()                                   │
│    └─► _cameraService.startImageStream(callback)          │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Frame Processing Pipeline

```
┌──────────────────────────────────────────────────────────────────┐
│                      Camera Captures Frame                        │
│                                                                   │
│  CameraImage (YUV420 format, e.g., 1920×1080)                    │
└────────────┬──────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│               Frame Callback in HomeScreen                       │
│                                                                  │
│  _runDetectionOnStream(CameraImage image)                       │
│    ├─ Check: _isProcessing? → Yes: DROP FRAME                  │
│    └─ No: Set _isProcessing = true, continue...                │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│           DetectionService.processFrame(image)                   │
│                                                                  │
│  STEP 1: Color Space Conversion                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ CameraService.convertYUV420ToImage()                    │   │
│  │   - Iterate over pixels                                 │   │
│  │   - Apply YUV → RGB formulas                            │   │
│  │   - Encode to JPEG                                      │   │
│  │   Output: Uint8List (JPEG bytes)                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│             │                                                    │
│             ▼                                                    │
│  STEP 2: Image Preprocessing                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ModelService.prepareImageForModel()                     │   │
│  │   - Decode JPEG → RGB Image                             │   │
│  │   - Resize to 640×640                                   │   │
│  │   - Normalize: (pixel/255 - mean) / std                 │   │
│  │   - Convert to CHW format (Channel, Height, Width)      │   │
│  │   - Convert to Float32List                              │   │
│  │   Output: Float32List[1, 3, 640, 640]                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│             │                                                    │
│             ▼                                                    │
│  STEP 3: Model Inference                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ModelService.runInference()                             │   │
│  │   - Create TensorData from Float32List                  │   │
│  │   - Call model.forward([inputTensor])                   │   │
│  │   - Wait for ExecuTorch runtime                         │   │
│  │   Output: [TensorData, TensorData]                      │   │
│  │     • outputs[0]: Logits [1, 100, 92]                   │   │
│  │     • outputs[1]: Boxes [1, 100, 4]                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│             │                                                    │
│             ▼                                                    │
│  STEP 4: Postprocessing                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ModelService.postprocess()                              │   │
│  │   A. Convert boxes: (cx,cy,w,h) → (x1,y1,x2,y2)        │   │
│  │   B. Scale coords: [0,1] → absolute pixels              │   │
│  │   C. Apply softmax to logits                            │   │
│  │   D. Get max class per box                              │   │
│  │   E. Filter by confidence > 0.5                         │   │
│  │   F. Remove NaN/infinite coordinates                    │   │
│  │   Output: List<DetectionResult>                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│             │                                                    │
│             ▼                                                    │
│  STEP 5: Format Conversion                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Convert DetectionResult → DetectionBox                  │   │
│  │   - Extract (x1, y1, x2, y2)                            │   │
│  │   - Calculate width = x2 - x1                           │   │
│  │   - Calculate height = y2 - y1                          │   │
│  │   - Validate coordinates                                │   │
│  │   Output: List<DetectionBox>                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│             │                                                    │
│             ▼                                                    │
│  Return DetectionResults(boxes, results, width, height)         │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│              Update UI State (setState)                          │
│                                                                  │
│  _detections = results.boxes                                    │
│  _detectionResults = results.results                            │
│  _originalImageSize = Size(...)                                 │
│  _isProcessing = false                                          │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Widget Rebuild (build)                         │
│                                                                  │
│  CameraPreviewWidget renders with new detections                │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│            DetectionPainter.paint() Called                       │
│                                                                  │
│  [See "Rendering Flow" diagram below]                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Rendering Flow (DetectionPainter)

```
┌──────────────────────────────────────────────────────────────────┐
│              DetectionPainter.paint(canvas, size)                 │
│                                                                   │
│  Input:                                                          │
│    - detections: List<DetectionBox> (in image space)            │
│    - originalImageSize: Size (camera resolution)                │
│    - canvas size: Size (screen dimensions)                      │
└────────────┬──────────────────────────────────────────────────────┘
             │
             ▼
     ┌──────────────────┐
     │ For each box:    │
     └────────┬─────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    STEP 1: Rotation Check                        │
│                                                                  │
│  isCanvasPortrait = canvas.height > canvas.width                │
│  isImageLandscape = image.width > image.height                  │
│  needsRotation = isCanvasPortrait && isImageLandscape           │
└────────────┬────────────────────────────────────────────────────┘
             │
             ├─► YES: needsRotation = true
             │   ┌───────────────────────────────────────────────┐
             │   │  Rotate 90° Counter-Clockwise                 │
             │   │                                               │
             │   │  boxX = detection.y                           │
             │   │  boxY = imageWidth - (detection.x + width)    │
             │   │  boxWidth = detection.height                  │
             │   │  boxHeight = detection.width                  │
             │   │                                               │
             │   │  Swap image dimensions:                       │
             │   │    rotatedWidth = imageHeight                 │
             │   │    rotatedHeight = imageWidth                 │
             │   └───────────────┬───────────────────────────────┘
             │                   │
             └─► NO: needsRotation = false
                 ┌───────────────┴───────────────────────────────┐
                 │  Use Original Coordinates                     │
                 │                                               │
                 │  boxX = detection.x                           │
                 │  boxY = detection.y                           │
                 │  boxWidth = detection.width                   │
                 │  boxHeight = detection.height                 │
                 └───────────────┬───────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                   STEP 2: Scaling to Canvas                      │
│                                                                  │
│  scaleX = canvasWidth / imageWidth                              │
│  scaleY = canvasHeight / imageHeight                            │
│  scale = min(scaleX, scaleY)    // Maintain aspect ratio        │
│                                                                  │
│  boxX *= scale                                                  │
│  boxY *= scale                                                  │
│  boxWidth *= scale                                              │
│  boxHeight *= scale                                             │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│               STEP 3: Centering (Letterboxing)                   │
│                                                                  │
│  scaledImageWidth = imageWidth * scale                          │
│  scaledImageHeight = imageHeight * scale                        │
│                                                                  │
│  offsetX = (canvasWidth - scaledImageWidth) / 2                 │
│  offsetY = (canvasHeight - scaledImageHeight) / 2               │
│                                                                  │
│  boxX += offsetX                                                │
│  boxY += offsetY                                                │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│                     STEP 4: Draw Rectangle                       │
│                                                                  │
│  rect = Rect.fromLTWH(boxX, boxY, boxWidth, boxHeight)         │
│  canvas.drawRect(rect, paint)                                   │
│    └─► paint: red, stroke, 3px width                            │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│               STEP 5: Draw Label (if available)                  │
│                                                                  │
│  label = "Class ${className}: ${confidence}%"                   │
│  textPainter.text = TextSpan(text: label, ...)                 │
│  textPainter.layout()                                           │
│  textPainter.paint(canvas, Offset(boxX, boxY - 20))            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Service Dependency Graph

```
┌─────────────────────────────────────────────────────────────────┐
│                         HomeScreen                               │
│                     (State Management)                           │
└───────┬──────────────────────┬─────────────────────┬────────────┘
        │                      │                     │
        │                      │                     │
        ▼                      ▼                     ▼
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│ ModelService │      │CameraService │      │   Detection  │
│              │      │              │      │   Service    │
│ • loadModel  │      │ • initialize │      │              │
│ • preprocess │      │ • convert    │      │ • orchestrate│
│ • inference  │      │   YUV420     │      │   pipeline   │
│ • postprocess│      │ • stream     │      │              │
└──────┬───────┘      └──────┬───────┘      └───┬──────┬───┘
       │                     │                  │      │
       │                     │                  │      │
       │        ┌────────────┘                  │      │
       │        │                               │      │
       └────────┴───────────────────────────────┘      │
                                                       │
                Depends on both services               │
                                                       │
                                                       ▼
                                          ┌────────────────────┐
                                          │  DetectionResults  │
                                          │   (Data Bundle)    │
                                          └─────────┬──────────┘
                                                    │
                                                    ▼
                                          ┌────────────────────┐
                                          │ CameraPreviewWidget│
                                          └─────────┬──────────┘
                                                    │
                                                    ▼
                                          ┌────────────────────┐
                                          │ DetectionPainter   │
                                          │  (CustomPainter)   │
                                          └────────────────────┘
```

---

## 5. Data Structure Flow

```
┌──────────────┐
│ CameraImage  │  YUV420 format from camera
└──────┬───────┘
       │ convertYUV420ToImage()
       ▼
┌──────────────┐
│ Uint8List    │  JPEG bytes
└──────┬───────┘
       │ prepareImageForModel()
       ▼
┌──────────────┐
│ Float32List  │  [1, 3, 640, 640] normalized tensor
└──────┬───────┘
       │ model.forward()
       ▼
┌──────────────┐
│ TensorData[] │  [logits, boxes] from model
└──────┬───────┘
       │ postprocess()
       ▼
┌──────────────────────┐
│ DetectionResult[]    │  Full detection info
│   - x1, y1, x2, y2   │  (corners format)
│   - confidence       │  (normalized coords)
│   - classId          │
│   - classConfidence  │
└──────┬───────────────┘
       │ convert to UI format
       ▼
┌──────────────────────┐
│ DetectionBox[]       │  Simple rectangles
│   - x, y             │  (absolute pixels)
│   - width, height    │
└──────┬───────────────┘
       │ passed to painter
       ▼
┌──────────────────────┐
│ Canvas rectangles    │  Drawn on screen
└──────────────────────┘
```

---

## 6. Coordinate Space Transformations

```
┌────────────────────────────────────────────────────────────────┐
│                    IMAGE SPACE                                  │
│                  (Camera Resolution)                            │
│                                                                 │
│  Origin: (0, 0) top-left                                       │
│  Dimensions: e.g., 1920 × 1080 (landscape)                     │
│  Units: Pixels                                                 │
│                                                                 │
│  ┌─────────────────────────┐                                   │
│  │  (100, 50)              │                                   │
│  │    ┌──────────┐         │  Example box:                     │
│  │    │  Person  │         │    x: 100, y: 50                  │
│  │    │          │         │    w: 200, h: 300                 │
│  │    └──────────┘         │                                   │
│  │      (300, 350)         │                                   │
│  └─────────────────────────┘                                   │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 ▼  Model outputs normalized (0-1)
┌────────────────────────────────────────────────────────────────┐
│                  NORMALIZED SPACE                               │
│                  (Model Outputs)                                │
│                                                                 │
│  Origin: (0, 0) top-left                                       │
│  Dimensions: 1.0 × 1.0                                         │
│  Units: Fractional (0.0 to 1.0)                                │
│                                                                 │
│  ┌─────────────────────────┐                                   │
│  │  (0.05, 0.05)           │                                   │
│  │    ┌──────────┐         │  Same box normalized:             │
│  │    │          │         │    x: 0.05, y: 0.05              │
│  │    └──────────┘         │    w: 0.10, h: 0.28              │
│  │      (0.16, 0.32)       │                                   │
│  └─────────────────────────┘                                   │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 ▼  Scale to image dimensions
┌────────────────────────────────────────────────────────────────┐
│               ABSOLUTE IMAGE SPACE                              │
│               (After Scaling)                                   │
│                                                                 │
│  Back to pixels: multiply by image width/height                │
│  x_abs = x_norm * image_width                                  │
│  y_abs = y_norm * image_height                                 │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 ▼  Transform to canvas
┌────────────────────────────────────────────────────────────────┐
│                   CANVAS SPACE                                  │
│               (UI Screen Rendering)                             │
│                                                                 │
│  Origin: (0, 0) top-left                                       │
│  Dimensions: e.g., 375 × 812 (iPhone portrait)                 │
│  Units: Logical pixels                                         │
│                                                                 │
│  Transformations:                                              │
│    1. Rotation (if portrait preview, landscape image)          │
│    2. Scaling (maintain aspect ratio)                          │
│    3. Centering (add offsets for letterbox)                    │
│                                                                 │
│  ┌─────────────────────────┐                                   │
│  │   (black bars)          │                                   │
│  │  ┌────────────────┐     │                                   │
│  │  │  ┌──────┐      │     │  Final box on screen              │
│  │  │  │Person│      │     │                                   │
│  │  │  └──────┘      │     │                                   │
│  │  └────────────────┘     │                                   │
│  │   (black bars)          │                                   │
│  └─────────────────────────┘                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. Model Architecture Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      DETR Model                                  │
│                                                                  │
│  Input: [1, 3, 640, 640] Float32                                │
└────────────┬─────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   ResNet-50 Backbone                             │
│                 (Feature Extraction)                             │
│                                                                  │
│  Convolutional layers extract visual features                   │
│  Output: Feature map (lower resolution, high dimensional)       │
└────────────┬─────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│              Transformer Encoder-Decoder                         │
│                 (Attention Mechanism)                            │
│                                                                  │
│  Encoder: Process image features                                │
│  Decoder: Generate 100 object queries                           │
│  Output: 100 learned object proposals                           │
└────────────┬─────────────────────────────────────────────────────┘
             │
             ├──────────────────────────────┬─────────────────────┘
             ▼                              ▼
┌──────────────────────────┐  ┌───────────────────────────────────┐
│  Classification Head     │  │   Box Regression Head             │
│                          │  │                                   │
│  Predicts object class   │  │   Predicts box coordinates        │
│  for each proposal       │  │   for each proposal               │
│                          │  │                                   │
│  Output: [1, 100, 92]    │  │   Output: [1, 100, 4]             │
│    • 100 proposals       │  │     • 100 proposals               │
│    • 92 classes          │  │     • 4 coords (cx, cy, w, h)     │
│      (91 COCO + bg)      │  │                                   │
└──────────────────────────┘  └───────────────────────────────────┘
```

---

## 8. Threading Model

```
┌─────────────────────────────────────────────────────────────────┐
│                         MAIN THREAD                              │
│                      (UI + State)                                │
│                                                                  │
│  • Flutter widget tree                                          │
│  • State management (setState)                                  │
│  • User interactions                                            │
│  • Rendering pipeline                                           │
└────────┬────────────────────────────────────────────────────────┘
         │
         │  Camera frame callback
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                  DETECTION PROCESSING                            │
│                   (Main Thread - Async)                          │
│                                                                  │
│  _runDetectionOnStream(image) async {                           │
│    if (_isProcessing) return;  // Drop frame                    │
│    _isProcessing = true;                                        │
│                                                                  │
│    // All processing happens here:                              │
│    await detectionService.processFrame(image);                  │
│      │                                                           │
│      ├─ YUV conversion (synchronous)                            │
│      ├─ Preprocessing (synchronous)                             │
│      ├─ Model inference (ExecuTorch internal threading)         │
│      └─ Postprocessing (synchronous)                            │
│                                                                  │
│    setState(() { ... });  // Update UI                          │
│    _isProcessing = false;                                       │
│  }                                                              │
│                                                                  │
│  Note: While processing, new frames are dropped                 │
└─────────────────────────────────────────────────────────────────┘
         │
         │  ExecuTorch may use internal thread pool
         ▼
┌─────────────────────────────────────────────────────────────────┐
│              EXECUTORCH RUNTIME                                  │
│           (Native C++ Threads)                                   │
│                                                                  │
│  • XNNPACK parallelism                                          │
│  • CPU core utilization                                         │
│  • Operator execution                                           │
│  • Memory management                                            │
└─────────────────────────────────────────────────────────────────┘
```

**Key Points**:
- Everything runs on main thread (Dart isolate)
- `async/await` doesn't create new threads
- ExecuTorch runtime uses internal C++ threads
- Frame dropping prevents UI blocking
- No manual threading needed

---

## 9. Performance Bottleneck Analysis

```
┌─────────────────────────────────────────────────────────────────┐
│                      Time per Frame                              │
│                                                                  │
│  ████████████████████████████████ Model Inference (70-80%)      │
│  ████████ Image Preprocessing (10-15%)                          │
│  ████ YUV Conversion (5-10%)                                    │
│  ██ Rendering (5%)                                              │
│                                                                  │
│  Total: ~50-200ms per frame (depending on device)               │
│  FPS: 5-20 FPS typical                                          │
└─────────────────────────────────────────────────────────────────┘

Optimization Opportunities:
1. Model size reduction → Biggest impact
2. Quantization (float32 → int8) → 2-4x speedup
3. Smaller input size (320×320) → 2x speedup
4. Skip frames (process every Nth) → N×FPS
5. GPU backend → 5-10x speedup
```

---

This document provides visual representations of all major flows in the CODS Mobile application. Use it alongside `ARCHITECTURE.md` for complete understanding.
