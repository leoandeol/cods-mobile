import 'dart:io';

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:executorch_flutter/executorch_flutter.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CODS Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightGreen[500]!),
      ),
      home: const MyHomePage(title: 'CODS Mobile'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class DetectionBox {
  final double x;
  final double y;
  final double width;
  final double height;

  DetectionBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class DetectionResult {
  final double x1, y1, x2, y2; // Bounding box coordinates
  final double confidence;
  final int classId;
  final double classConfidence;

  DetectionResult({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.classId,
    required this.classConfidence,
  });
}

const List<String> classNames = [
  'person',
  'bicycle',
  'car',
  'motorbike',
  'aeroplane',
  'bus',
  'train',
  'truck',
  'boat',
  'trafficlight',
  'firehydrant',
  'streetsign',
  'stopsign',
  'parkingmeter',
  'bench',
  'bird',
  'cat',
  'dog',
  'horse',
  'sheep',
  'cow',
  'elephant',
  'bear',
  'zebra',
  'giraffe',
  'hat',
  'backpack',
  'umbrella',
  'shoe',
  'eyeglasses',
  'handbag',
  'tie',
  'suitcase',
  'frisbee',
  'skis',
  'snowboard',
  'sportsball',
  'kite',
  'baseballbat',
  'baseballglove',
  'skateboard',
  'surfboard',
  'tennisracket',
  'bottle',
  'plate',
  'wineglass',
  'cup',
  'fork',
  'knife',
  'spoon',
  'bowl',
  'banana',
  'apple',
  'sandwich',
  'orange',
  'broccoli',
  'carrot',
  'hotdog',
  'pizza',
  'donut',
  'cake',
  'chair',
  'sofa',
  'pottedplant',
  'bed',
  'mirror',
  'diningtable',
  'window',
  'desk',
  'toilet',
  'door',
  'tvmonitor',
  'laptop',
  'mouse',
  'remote',
  'keyboard',
  'cellphone',
  'microwave',
  'oven',
  'toaster',
  'sink',
  'refrigerator',
  'blender',
  'book',
  'clock',
  'vase',
  'scissors',
  'teddybear',
  'hairdrier',
  'toothbrush',
  'hairbrush',
];

class DetectionPainter extends CustomPainter {
  final List<DetectionBox> detections;
  final List<DetectionResult>? detectionResults; // Optional for showing labels
  final Size originalImageSize;

  DetectionPainter(
    this.detections, {
    this.detectionResults,
    required this.originalImageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Debug output
    print('\n########## DETECTION PAINTER ##########');
    print('Canvas size: ${size.width} x ${size.height}');
    print(
      'Original image size: ${originalImageSize.width} x ${originalImageSize.height}',
    );
    print('Number of detections: ${detections.length}');

    // Determine if we need to rotate coordinates
    // Canvas (preview) is portrait if height > width
    // Image is landscape if width > height
    final isCanvasPortrait = size.height > size.width;
    final isImageLandscape = originalImageSize.width > originalImageSize.height;
    final needsRotation = isCanvasPortrait && isImageLandscape;

    print(
      'Canvas portrait: $isCanvasPortrait, Image landscape: $isImageLandscape, Needs rotation: $needsRotation',
    );

    for (int i = 0; i < detections.length; i++) {
      final detection = detections[i];

      if (i < 3) {
        // Only print detailed logs for first 3
        print('\n--- Processing detection $i ---');
        print(
          'Input box: x=${detection.x}, y=${detection.y}, w=${detection.width}, h=${detection.height}',
        );
      }

      double boxX, boxY, boxWidth, boxHeight;

      if (needsRotation) {
        // Rotate 90 degrees counter-clockwise: (x, y) -> (y, width - x)
        // The box (x, y, w, h) becomes:
        boxX = detection.y;
        boxY = originalImageSize.width - (detection.x + detection.width);
        boxWidth = detection.height;
        boxHeight = detection.width;

        if (i < 3)
          print('After rotation: x=$boxX, y=$boxY, w=$boxWidth, h=$boxHeight');

        // Now scale to fit the canvas (portrait)
        // After rotation, image dimensions are swapped
        final rotatedImageWidth = originalImageSize.height;
        final rotatedImageHeight = originalImageSize.width;

        if (i < 3)
          print(
            'Rotated image dimensions: ${rotatedImageWidth} x ${rotatedImageHeight}',
          );

        final scaleX = size.width / rotatedImageWidth;
        final scaleY = size.height / rotatedImageHeight;
        final scale = math.min(scaleX, scaleY);

        if (i < 3)
          print(
            'Scale factors: scaleX=$scaleX, scaleY=$scaleY, chosen scale=$scale',
          );

        boxX *= scale;
        boxY *= scale;
        boxWidth *= scale;
        boxHeight *= scale;

        if (i < 3)
          print('After scaling: x=$boxX, y=$boxY, w=$boxWidth, h=$boxHeight');

        // Center if needed
        final scaledWidth = rotatedImageWidth * scale;
        final scaledHeight = rotatedImageHeight * scale;
        final offsetX = (size.width - scaledWidth) / 2;
        final offsetY = (size.height - scaledHeight) / 2;

        if (i < 3)
          print('Centering offsets: offsetX=$offsetX, offsetY=$offsetY');

        boxX += offsetX;
        boxY += offsetY;

        if (i < 3)
          print('After centering: x=$boxX, y=$boxY, w=$boxWidth, h=$boxHeight');
      } else {
        // No rotation needed, just scale
        final scaleX = size.width / originalImageSize.width;
        final scaleY = size.height / originalImageSize.height;
        final scale = math.min(scaleX, scaleY);

        if (i < 3)
          print(
            'Scale factors: scaleX=$scaleX, scaleY=$scaleY, chosen scale=$scale',
          );

        boxX = detection.x * scale;
        boxY = detection.y * scale;
        boxWidth = detection.width * scale;
        boxHeight = detection.height * scale;

        if (i < 3)
          print('After scaling: x=$boxX, y=$boxY, w=$boxWidth, h=$boxHeight');

        // Center if needed
        final scaledWidth = originalImageSize.width * scale;
        final scaledHeight = originalImageSize.height * scale;
        final offsetX = (size.width - scaledWidth) / 2;
        final offsetY = (size.height - scaledHeight) / 2;

        if (i < 3)
          print('Centering offsets: offsetX=$offsetX, offsetY=$offsetY');

        boxX += offsetX;
        boxY += offsetY;

        if (i < 3)
          print('After centering: x=$boxX, y=$boxY, w=$boxWidth, h=$boxHeight');
      }

      if (i < 3) {
        print('FINAL canvas box: x=$boxX, y=$boxY, w=$boxWidth, h=$boxHeight');
        print(
          'Canvas bounds check: x in [0, ${size.width}]? ${boxX >= 0 && boxX <= size.width}',
        );
        print(
          'Canvas bounds check: y in [0, ${size.height}]? ${boxY >= 0 && boxY <= size.height}',
        );
        print(
          'Canvas bounds check: x+w in [0, ${size.width}]? ${(boxX + boxWidth) >= 0 && (boxX + boxWidth) <= size.width}',
        );
        print(
          'Canvas bounds check: y+h in [0, ${size.height}]? ${(boxY + boxHeight) >= 0 && (boxY + boxHeight) <= size.height}',
        );
      }

      final rect = Rect.fromLTWH(boxX, boxY, boxWidth, boxHeight);
      canvas.drawRect(rect, paint);

      // Draw label if available
      if (detectionResults != null && i < detectionResults!.length) {
        final result = detectionResults![i];
        final label =
            'Class ${classNames[result.classId - 1]}: ${(result.confidence * 100).toStringAsFixed(1)}%';

        textPainter.text = TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            backgroundColor: Colors.red,
            fontSize: 14,
          ),
        );

        textPainter.layout();
        textPainter.paint(canvas, Offset(boxX, boxY - 20));
      }
    }

    print('########## END DETECTION PAINTER ##########\n');
  }

  @override
  bool shouldRepaint(DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.originalImageSize != originalImageSize;
  }
}

class _MyHomePageState extends State<MyHomePage> {
  late ExecuTorchModel model;
  int _counter = 0;
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  int _currentCameraIndex = 0;
  Timer? _detectionTimer;
  List<DetectionBox> _detections = [];
  List<DetectionResult> _detectionResults = []; // Add this
  Size _originalImageSize = const Size(1, 1); // Store original image size
  bool _isProcessing = false; // Flag to prevent concurrent processing

  @override
  void initState() {
    loadModel();
    initializeCamera(_currentCameraIndex);
    super.initState();
  }

  Future<void> loadModel() async {
    final byteData = await rootBundle.load('assets/model.pte');
    final tempDir = await getTemporaryDirectory();

    // Use versioned filename to force reload (increment when model changes)
    final file = File('${tempDir.path}/model_v2.pte');

    // Always overwrite to ensure fresh model
    if (await file.exists()) {
      await file.delete();
    }
    await file.writeAsBytes(byteData.buffer.asUint8List());

    print('[MODEL] Loading model from: ${file.path}');
    print('[MODEL] Model file size: ${await file.length()} bytes');

    // Load and run inference
    model = await ExecuTorchModel.load(file.path);

    print('[MODEL] Model loaded successfully!');
  }

  Future<void> initializeCamera(int cameraIndex) async {
    if (cameras.isEmpty) {
      return;
    }

    // Dispose of previous controller if it exists
    await _cameraController?.dispose();
    _detectionTimer?.cancel();

    _cameraController = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();
    if (mounted) {
      setState(() {
        _isCameraInitialized = true;
      });

      // Start image streaming for detection instead of timer
      _cameraController!.startImageStream((CameraImage image) {
        // Only process if not already processing
        if (!_isProcessing) {
          _runDetectionOnStream(image);
        }
      });
    }
  }

  Future<void> _runDetectionOnStream(CameraImage image) async {
    if (_isProcessing) return;

    _isProcessing = true;

    try {
      List<DetectionBox> detections = await _processFrameFromStream(image);

      if (mounted) {
        setState(() {
          _detections = detections;
          // _detectionResults is set in _processFrameFromStream
        });
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _runDetection() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    List<DetectionBox> detections = await _processFrame();

    if (mounted) {
      setState(() {
        _detections = detections;
        // _detectionResults is set in _processFrame
      });
    }
  }

  Float32List prepareImageForModel(Uint8List imageBytes) {
    // Decode image
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('Failed to decode image');

    print('[PREPROCESSING] Original image: ${image.width}x${image.height}');

    // Resize to 640x640
    img.Image resized = img.copyResize(image, width: 640, height: 640);

    print('[PREPROCESSING] Resized to: ${resized.width}x${resized.height}');

    // Convert to RGB if needed
    if (resized.numChannels == 4) {
      resized = img.copyResize(resized, width: 640, height: 640);
    }

    // ImageNet normalization values (DETR requires this!)
    const meanR = 0.485;
    const meanG = 0.456;
    const meanB = 0.406;
    const stdR = 0.229;
    const stdG = 0.224;
    const stdB = 0.225;

    // Prepare float buffer: 1 * 3 * 640 * 640 = 150528
    final float32list = Float32List(1 * 3 * 640 * 640);

    int pixelIndex = 0;

    // Convert to CHW format (Channel, Height, Width) with ImageNet normalization
    // Fill Red channel
    for (int y = 0; y < 640; y++) {
      for (int x = 0; x < 640; x++) {
        final pixel = resized.getPixel(x, y);
        float32list[pixelIndex++] = (pixel.r / 255.0 - meanR) / stdR;
      }
    }

    // Fill Green channel
    for (int y = 0; y < 640; y++) {
      for (int x = 0; x < 640; x++) {
        final pixel = resized.getPixel(x, y);
        float32list[pixelIndex++] = (pixel.g / 255.0 - meanG) / stdG;
      }
    }

    // Fill Blue channel
    for (int y = 0; y < 640; y++) {
      for (int x = 0; x < 640; x++) {
        final pixel = resized.getPixel(x, y);
        float32list[pixelIndex++] = (pixel.b / 255.0 - meanB) / stdB;
      }
    }

    // Print sample values from the tensor
    print('[PREPROCESSING] Sample tensor values (first 10):');
    for (int i = 0; i < math.min(10, float32list.length); i++) {
      print('  [$i] = ${float32list[i]}');
    }
    print(
      '[PREPROCESSING] Tensor min/max: ${float32list.reduce(math.min)} / ${float32list.reduce(math.max)}',
    );

    return float32list;
  }

  // Convert box format from [cx, cy, w, h] to [x1, y1, x2, y2]
  Float32List boxCxcywhToXyxy(Float32List boxes, List<int> shape) {
    // shape is [1, 100, 4]
    final numBoxes = shape[1];
    final result = Float32List(boxes.length);

    for (int i = 0; i < numBoxes; i++) {
      final offset = i * 4;
      final cx = boxes[offset + 0];
      final cy = boxes[offset + 1];
      final w = boxes[offset + 2];
      final h = boxes[offset + 3];

      // Convert to corners format
      result[offset + 0] = cx - w / 2; // x1
      result[offset + 1] = cy - h / 2; // y1
      result[offset + 2] = cx + w / 2; // x2
      result[offset + 3] = cy + h / 2; // y2
    }

    return result;
  }

  // Softmax along last dimension
  Float32List softmaxLastDim(Float32List data, List<int> shape) {
    // shape is [1, 100, 92]
    final batch = shape[0];
    final numBoxes = shape[1];
    final numClasses = shape[2];

    final result = Float32List(data.length);

    for (int b = 0; b < batch; b++) {
      for (int i = 0; i < numBoxes; i++) {
        final offset = (b * numBoxes * numClasses) + (i * numClasses);

        // Find max for numerical stability
        double maxVal = data[offset];
        for (int c = 1; c < numClasses; c++) {
          maxVal = math.max(maxVal, data[offset + c]);
        }

        // Compute exp and sum
        double sum = 0.0;
        for (int c = 0; c < numClasses; c++) {
          result[offset + c] = math.exp(data[offset + c] - maxVal);
          sum += result[offset + c];
        }

        // Normalize
        for (int c = 0; c < numClasses; c++) {
          result[offset + c] /= sum;
        }
      }
    }

    return result;
  }

  // Get max value and index along last dimension
  List<Map<String, double>> maxLastDim(Float32List data, List<int> shape) {
    // shape is [1, 100, 92]
    final numBoxes = shape[1];
    final numClasses = shape[2];

    final results = <Map<String, double>>[];

    for (int i = 0; i < numBoxes; i++) {
      final offset = i * numClasses;

      double maxVal = data[offset];
      int maxIdx = 0;

      for (int c = 1; c < numClasses; c++) {
        if (data[offset + c] > maxVal) {
          maxVal = data[offset + c];
          maxIdx = c;
        }
      }

      results.add({'value': maxVal, 'index': maxIdx.toDouble()});
    }

    return results;
  }

  List<DetectionResult> postprocess(
    TensorData outLogits,
    TensorData outBboxes,
    double imgWidth,
    double imgHeight,
  ) {
    print('==================================================');
    print('POSTPROCESS START');
    print(
      'Input tensor data lengths: logits=${outLogits.data.length} bytes, boxes=${outBboxes.data.length} bytes',
    );

    // Check raw bytes first
    print(
      'First 16 bytes of box data (as Uint8): ${outBboxes.data.sublist(0, math.min(16, outBboxes.data.length))}',
    );

    // Convert to Float32List
    //final logitsData = outLogits.data.buffer.asFloat32List();
    //final boxesData = outBboxes.data.buffer.asFloat32List();
    final bytelogitsData = ByteData.sublistView(outLogits.data);
    final floatCountLogits = outLogits.data.length ~/ 4;
    final logitsData = Float32List(floatCountLogits);
    for (int i = 0; i < floatCountLogits; i++) {
      logitsData[i] = bytelogitsData.getFloat32(i * 4, Endian.host);
    }

    final byteboxesData = ByteData.sublistView(outBboxes.data);
    final floatCountBoxes = outBboxes.data.length ~/ 4;
    final boxesData = Float32List(floatCountBoxes);
    for (int i = 0; i < floatCountBoxes; i++) {
      boxesData[i] = byteboxesData.getFloat32(i * 4, Endian.host);
    }

    print(
      'Float32List lengths: logits=${logitsData.length} floats, boxes=${boxesData.length} floats',
    );
    print(
      'First 10 box float values: ${boxesData.sublist(0, math.min(10, boxesData.length))}',
    );

    final logitsShape = outLogits.shape.map((e) => e ?? 1).toList();
    final boxesShape = outBboxes.shape.map((e) => e ?? 1).toList();

    final numBoxes = boxesShape[1]; // 100
    final numClasses = logitsShape[2]; // 92

    print('Processing $numBoxes boxes with $numClasses classes');
    print('Image dimensions: $imgWidth x $imgHeight');
    print('==================================================');

    // Print first raw box from model
    print(
      'Raw box 0 (cx,cy,w,h): [${boxesData[0]}, ${boxesData[1]}, ${boxesData[2]}, ${boxesData[3]}]',
    );

    // 1. Convert boxes from [cx, cy, w, h] to [x1, y1, x2, y2]
    final xyxyBoxes = boxCxcywhToXyxy(boxesData, boxesShape);

    print('After cxcywh->xyxy conversion (normalized 0-1):');
    print(
      '  Box 0: [${xyxyBoxes[0]}, ${xyxyBoxes[1]}, ${xyxyBoxes[2]}, ${xyxyBoxes[3]}]',
    );
    print(
      '  Width: ${xyxyBoxes[2] - xyxyBoxes[0]}, Height: ${xyxyBoxes[3] - xyxyBoxes[1]}',
    );

    // 2. Scale boxes from relative [0, 1] to absolute coordinates
    final scaledBoxes = Float32List(xyxyBoxes.length);
    for (int i = 0; i < numBoxes; i++) {
      final offset = i * 4;
      scaledBoxes[offset + 0] = xyxyBoxes[offset + 0] * imgWidth; // x1
      scaledBoxes[offset + 1] = xyxyBoxes[offset + 1] * imgHeight; // y1
      scaledBoxes[offset + 2] = xyxyBoxes[offset + 2] * imgWidth; // x2
      scaledBoxes[offset + 3] = xyxyBoxes[offset + 3] * imgHeight; // y2
    }

    print('After scaling to image dimensions:');
    print(
      '  Box 0: [${scaledBoxes[0]}, ${scaledBoxes[1]}, ${scaledBoxes[2]}, ${scaledBoxes[3]}]',
    );
    print(
      '  Width: ${scaledBoxes[2] - scaledBoxes[0]}, Height: ${scaledBoxes[3] - scaledBoxes[1]}',
    );

    // 3. Apply softmax to logits
    final softmaxLogits = softmaxLastDim(logitsData, logitsShape);

    // 4. Get class probabilities (exclude last class - background)
    final classProbsPerBox = <List<double>>[];
    for (int i = 0; i < numBoxes; i++) {
      final offset = i * numClasses;
      final probs = <double>[];
      for (int c = 0; c < numClasses - 1; c++) {
        probs.add(softmaxLogits[offset + c]);
      }
      classProbsPerBox.add(probs);
    }

    // 5. Get confidences (max probability across classes, excluding background)
    final confidences = <double>[];
    final predictedClasses = <int>[];

    for (int i = 0; i < numBoxes; i++) {
      final probs = classProbsPerBox[i];
      double maxProb = probs[0];
      int maxClass = 0;

      for (int c = 1; c < probs.length; c++) {
        if (probs[c] > maxProb) {
          maxProb = probs[c];
          maxClass = c;
        }
      }

      confidences.add(maxProb);
      predictedClasses.add(maxClass);
    }

    // 6. Filter by confidence threshold and validate coordinates
    final detections = <DetectionResult>[];
    const confidenceThreshold = 0.5;

    print('Filtering detections with confidence > $confidenceThreshold');
    int validCount = 0;

    for (int i = 0; i < numBoxes; i++) {
      if (confidences[i] > confidenceThreshold) {
        final offset = i * 4;

        final x1 = scaledBoxes[offset + 0];
        final y1 = scaledBoxes[offset + 1];
        final x2 = scaledBoxes[offset + 2];
        final y2 = scaledBoxes[offset + 3];

        // Skip if any coordinate is NaN or infinite
        if (x1.isNaN ||
            y1.isNaN ||
            x2.isNaN ||
            y2.isNaN ||
            x1.isInfinite ||
            y1.isInfinite ||
            x2.isInfinite ||
            y2.isInfinite) {
          print('Skipping invalid box at index $i: [$x1, $y1, $x2, $y2]');
          continue;
        }

        validCount++;
        if (validCount <= 3) {
          // Only print first 3 to avoid spam
          print(
            'Detection $validCount: conf=${confidences[i].toStringAsFixed(3)}, box=[$x1, $y1, $x2, $y2], w=${x2 - x1}, h=${y2 - y1}',
          );
        }

        detections.add(
          DetectionResult(
            x1: x1,
            y1: y1,
            x2: x2,
            y2: y2,
            confidence: confidences[i],
            classId: predictedClasses[i],
            classConfidence: classProbsPerBox[i][predictedClasses[i]],
          ),
        );
      }
    }

    print('Filtered to ${detections.length} valid detections above threshold');
    print('==================================================');

    return detections;
  }

  Future<List<DetectionBox>> _processFrame() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return [];
    }

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      final Uint8List imageBytes = await imageFile.readAsBytes();

      // Get original image dimensions
      final img.Image? originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) throw Exception('Failed to decode image');

      final originalWidth = originalImage.width.toDouble();
      final originalHeight = originalImage.height.toDouble();

      print('Original image size: $originalWidth x $originalHeight');

      // Store the actual camera image size (not rotated)
      _originalImageSize = Size(originalWidth, originalHeight);

      print('Preview size: ${_cameraController!.value.previewSize}');
      print('Aspect ratio: ${_cameraController!.value.aspectRatio}');

      final Float32List processedImage = prepareImageForModel(imageBytes);
      final Uint8List tensorBytes = processedImage.buffer.asUint8List();
      final inputTensor = TensorData(
        shape: [1, 3, 640, 640],
        dataType: TensorType.float32,
        data: tensorBytes,
      );

      // Run inference
      print(
        '[INFERENCE] Calling model.forward() with input shape: ${inputTensor.shape}',
      );
      print('[INFERENCE] Input data length: ${inputTensor.data.length} bytes');

      final outputs = await model.forward([inputTensor]);

      print('[INFERENCE] Got ${outputs.length} outputs');
      if (outputs.length >= 2) {
        print(
          '[INFERENCE] Output 0 shape: ${outputs[0].shape}, data length: ${outputs[0].data.length}',
        );
        print(
          '[INFERENCE] Output 1 shape: ${outputs[1].shape}, data length: ${outputs[1].data.length}',
        );
      }

      if (outputs.length < 2) return [];

      final outputClassif = outputs[0];
      final outputBoxes = outputs[1];

      print('Classification shape: ${outputClassif.shape}');
      print('Boxes shape: ${outputBoxes.shape}');

      // Post-process using the ACTUAL captured image dimensions
      final detections = postprocess(
        outputClassif,
        outputBoxes,
        originalWidth,
        originalHeight,
      );

      // Store detection results for labels
      _detectionResults = detections;

      // Convert to DetectionBox format - use coordinates as-is from detection
      final detectionBoxes = <DetectionBox>[];

      for (var det in detections) {
        // Validate coordinates
        if (det.x1.isNaN || det.y1.isNaN || det.x2.isNaN || det.y2.isNaN) {
          print(
            'Warning: NaN coordinates in detection: x1=${det.x1}, y1=${det.y1}, x2=${det.x2}, y2=${det.y2}',
          );
          continue;
        }

        if (det.x1.isInfinite ||
            det.y1.isInfinite ||
            det.x2.isInfinite ||
            det.y2.isInfinite) {
          print('Warning: Infinite coordinates in detection');
          continue;
        }

        // Use coordinates directly from detection (in camera image space)
        detectionBoxes.add(
          DetectionBox(
            x: det.x1,
            y: det.y1,
            width: det.x2 - det.x1,
            height: det.y2 - det.y1,
          ),
        );

        print(
          'Added box: x=${det.x1}, y=${det.y1}, w=${det.x2 - det.x1}, h=${det.y2 - det.y1}',
        );
      }

      print('Valid detections: ${detectionBoxes.length}');
      return detectionBoxes;
    } catch (e) {
      print('Error capturing frame: $e');
      return [];
    }
  }

  // Convert YUV420 CameraImage to Uint8List (JPEG bytes)
  Uint8List _convertYUV420ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    // Create an Image object from YUV420
    final img.Image imgLib = img.Image(width: width, height: height);

    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel!;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex =
            uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
        final int index = y * width + x;

        final yp = image.planes[0].bytes[index];
        final up = image.planes[1].bytes[uvIndex];
        final vp = image.planes[2].bytes[uvIndex];

        // Convert YUV to RGB
        int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .round()
            .clamp(0, 255);
        int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

        imgLib.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    // Encode to JPEG
    return Uint8List.fromList(img.encodeJpg(imgLib));
  }

  Future<List<DetectionBox>> _processFrameFromStream(CameraImage image) async {
    try {
      // Convert CameraImage to bytes
      final Uint8List imageBytes = _convertYUV420ToImage(image);

      final originalWidth = image.width.toDouble();
      final originalHeight = image.height.toDouble();

      print('\n========== PROCESSING FRAME FROM STREAM ==========');
      print('Stream image size: $originalWidth x $originalHeight');

      // Store the actual camera image size (not rotated)
      _originalImageSize = Size(originalWidth, originalHeight);
      print(
        'Stored _originalImageSize: ${_originalImageSize.width} x ${_originalImageSize.height}',
      );

      final Float32List processedImage = prepareImageForModel(imageBytes);
      final Uint8List tensorBytes = processedImage.buffer.asUint8List();
      final inputTensor = TensorData(
        shape: [1, 3, 640, 640],
        dataType: TensorType.float32,
        data: tensorBytes,
      );

      // Run inference
      print(
        '[INFERENCE] Calling model.forward() with input shape: ${inputTensor.shape}',
      );
      print('[INFERENCE] Input data length: ${inputTensor.data.length} bytes');

      final outputs = await model.forward([inputTensor]);

      print('[INFERENCE] Got ${outputs.length} outputs');
      if (outputs.length >= 2) {
        print(
          '[INFERENCE] Output 0 shape: ${outputs[0].shape}, data length: ${outputs[0].data.length}',
        );
        print(
          '[INFERENCE] Output 1 shape: ${outputs[1].shape}, data length: ${outputs[1].data.length}',
        );
      }

      if (outputs.length < 2) return [];

      final outputClassif = outputs[0];
      final outputBoxes = outputs[1];

      // Post-process using the ACTUAL captured image dimensions
      final detections = postprocess(
        outputClassif,
        outputBoxes,
        originalWidth,
        originalHeight,
      );

      // Store detection results for labels
      _detectionResults = detections;

      // Convert to DetectionBox format - use coordinates directly
      final detectionBoxes = <DetectionBox>[];

      print(
        '\nConverting ${detections.length} DetectionResults to DetectionBoxes:',
      );
      int boxNum = 0;
      for (var det in detections) {
        // Validate coordinates
        if (det.x1.isNaN || det.y1.isNaN || det.x2.isNaN || det.y2.isNaN) {
          continue;
        }

        if (det.x1.isInfinite ||
            det.y1.isInfinite ||
            det.x2.isInfinite ||
            det.y2.isInfinite) {
          continue;
        }

        // Use coordinates directly from detection (in camera image space)
        final box = DetectionBox(
          x: det.x1,
          y: det.y1,
          width: det.x2 - det.x1,
          height: det.y2 - det.y1,
        );

        if (boxNum < 3) {
          // Only log first 3
          print(
            '  Box $boxNum: x=${box.x}, y=${box.y}, w=${box.width}, h=${box.height}',
          );
        }
        boxNum++;

        detectionBoxes.add(box);
      }

      print('Created ${detectionBoxes.length} DetectionBoxes');
      print('==================================================\n');

      return detectionBoxes;
    } catch (e) {
      print('Error processing stream frame: $e');
      return [];
    }
  }

  Future<void> switchCamera() async {
    if (cameras.length < 2) {
      return;
    }

    // Stop image stream before switching
    await _cameraController?.stopImageStream();

    setState(() {
      _isCameraInitialized = false;
    });

    _currentCameraIndex = (_currentCameraIndex + 1) % cameras.length;
    await initializeCamera(_currentCameraIndex);
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _cameraController?.stopImageStream().catchError((_) {});
    _cameraController?.dispose();
    model.dispose();
    super.dispose();
  }

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
        toolbarHeight: 70,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_isCameraInitialized && _cameraController != null)
              Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width, // * 0.9,
                      maxHeight: MediaQuery.of(
                        context,
                      ).size.height, // * 0.88, // * 0.6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: AspectRatio(
                      aspectRatio: _cameraController!.value.aspectRatio,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Transform.scale(
                                scaleX: -1,
                                child: CameraPreview(_cameraController!),
                              ),
                              CustomPaint(
                                painter: DetectionPainter(
                                  _detections,
                                  detectionResults: _detectionResults,
                                  originalImageSize: _originalImageSize,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  if (cameras.length > 1)
                    Positioned(
                      bottom: 32,
                      width: 70,
                      height: 70,
                      child: FloatingActionButton(
                        mini: false,
                        onPressed: switchCamera,
                        tooltip: 'Switch Camera',
                        child: const Icon(Icons.flip_camera_ios, size: 50),
                      ),
                    ),
                ],
              )
            else
              SizedBox(
                width: MediaQuery.of(context).size.width, // * 0.9,
                height: MediaQuery.of(context).size.height, // * 0.6,
                child: const Center(child: CircularProgressIndicator()),
              ),
            //const SizedBox(height: 20),
            //const Text('You have pushed the button this many times:'),
            // Text(
            //   '$_counter',
            //   style: Theme.of(context).textTheme.headlineMedium,
            // ),
          ],
        ),
      ),
      // floatingActionButton: FloatingActionButton(
      //   onPressed: _incrementCounter,
      //   tooltip: 'Increment',
      //   child: const Icon(Icons.add),
      // ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
