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
      title: 'Flutter Demo',
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
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

class DetectionPainter extends CustomPainter {
  final List<DetectionBox> detections;
  final List<DetectionResult>? detectionResults; // Optional for showing labels

  DetectionPainter(this.detections, {this.detectionResults});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < detections.length; i++) {
      final detection = detections[i];

      final rect = Rect.fromLTWH(
        detection.x,
        detection.y,
        detection.width,
        detection.height,
      );
      canvas.drawRect(rect, paint);

      // Draw label if available
      if (detectionResults != null && i < detectionResults!.length) {
        final result = detectionResults![i];
        final label =
            'Class ${result.classId}: ${(result.confidence * 100).toStringAsFixed(1)}%';

        textPainter.text = TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            backgroundColor: Colors.red,
            fontSize: 14,
          ),
        );

        textPainter.layout();
        textPainter.paint(canvas, Offset(detection.x, detection.y - 20));
      }
    }
  }

  @override
  bool shouldRepaint(DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections;
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

  @override
  void initState() {
    loadModel();
    initializeCamera(_currentCameraIndex);
    super.initState();
  }

  Future<void> loadModel() async {
    final byteData = await rootBundle.load('assets/model.pte');
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/model.pte');
    await file.writeAsBytes(byteData.buffer.asUint8List());

    // Load and run inference
    model = await ExecuTorchModel.load(file.path);
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
    );

    await _cameraController!.initialize();
    if (mounted) {
      setState(() {
        _isCameraInitialized = true;
      });

      // Start the detection timer
      _detectionTimer = Timer.periodic(const Duration(milliseconds: 500), (
        timer,
      ) {
        _runDetection();
      });
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

    // Resize to 224x224
    img.Image resized = img.copyResize(image, width: 224, height: 224);

    // Convert to RGB if needed
    if (resized.numChannels == 4) {
      resized = img.copyResize(resized, width: 224, height: 224);
    }

    // Prepare float buffer: 1 * 3 * 224 * 224 = 150528
    final float32list = Float32List(1 * 3 * 224 * 224);

    int pixelIndex = 0;

    // Convert to CHW format (Channel, Height, Width)
    // Fill Red channel
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resized.getPixel(x, y);
        float32list[pixelIndex++] = pixel.r / 255.0; // Normalize to 0-1
      }
    }

    // Fill Green channel
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resized.getPixel(x, y);
        float32list[pixelIndex++] = pixel.g / 255.0;
      }
    }

    // Fill Blue channel
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resized.getPixel(x, y);
        float32list[pixelIndex++] = pixel.b / 255.0;
      }
    }

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
    // Convert to Float32List
    final logitsData = outLogits.data.buffer.asFloat32List();
    final boxesData = outBboxes.data.buffer.asFloat32List();

    // Check for NaN in raw data
    bool hasNaN = false;
    for (int i = 0; i < math.min(10, boxesData.length); i++) {
      if (boxesData[i].isNaN) {
        print('Warning: NaN found in raw box data at index $i');
        hasNaN = true;
      }
    }

    final logitsShape = outLogits.shape.map((e) => e ?? 1).toList();
    final boxesShape = outBboxes.shape.map((e) => e ?? 1).toList();

    final numBoxes = boxesShape[1]; // 100
    final numClasses = logitsShape[2]; // 92

    print('Processing $numBoxes boxes with $numClasses classes');
    print('Image dimensions: $imgWidth x $imgHeight');

    // 1. Convert boxes from [cx, cy, w, h] to [x1, y1, x2, y2]
    final xyxyBoxes = boxCxcywhToXyxy(boxesData, boxesShape);

    // 2. Scale boxes from relative [0, 1] to absolute coordinates
    final scaledBoxes = Float32List(xyxyBoxes.length);
    for (int i = 0; i < numBoxes; i++) {
      final offset = i * 4;
      scaledBoxes[offset + 0] = xyxyBoxes[offset + 0] * imgWidth; // x1
      scaledBoxes[offset + 1] = xyxyBoxes[offset + 1] * imgHeight; // y1
      scaledBoxes[offset + 2] = xyxyBoxes[offset + 2] * imgWidth; // x2
      scaledBoxes[offset + 3] = xyxyBoxes[offset + 3] * imgHeight; // y2
    }

    // Debug: print first few scaled boxes
    print(
      'First scaled box: [${scaledBoxes[0]}, ${scaledBoxes[1]}, ${scaledBoxes[2]}, ${scaledBoxes[3]}]',
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

      final Float32List processedImage = prepareImageForModel(imageBytes);
      final Uint8List tensorBytes = processedImage.buffer.asUint8List();
      final inputTensor = TensorData(
        shape: [1, 3, 224, 224],
        dataType: TensorType.float32,
        data: tensorBytes,
      );

      // Run inference
      final outputs = await model.forward([inputTensor]);

      if (outputs.length < 2) return [];

      final outputClassif = outputs[0];
      final outputBoxes = outputs[1];

      print('Classification shape: ${outputClassif.shape}');
      print('Boxes shape: ${outputBoxes.shape}');

      // Post-process
      final detections = postprocess(
        outputClassif,
        outputBoxes,
        originalWidth,
        originalHeight,
      );

      // Store detection results for labels
      _detectionResults = detections;

      // Get camera preview size
      final previewSize = _cameraController!.value.previewSize;
      if (previewSize == null) {
        print('Preview size is null');
        return [];
      }

      print('Preview size: ${previewSize.width} x ${previewSize.height}');

      final scaleX = previewSize.width / originalWidth;
      final scaleY = previewSize.height / originalHeight;

      print('Scale factors: scaleX=$scaleX, scaleY=$scaleY');

      // Convert to DetectionBox format for display with validation
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

        final x = det.x1 * scaleX;
        final y = det.y1 * scaleY;
        final width = (det.x2 - det.x1) * scaleX;
        final height = (det.y2 - det.y1) * scaleY;

        // Validate scaled coordinates
        if (x.isNaN || y.isNaN || width.isNaN || height.isNaN) {
          print('Warning: NaN after scaling: x=$x, y=$y, w=$width, h=$height');
          continue;
        }

        // Clamp to valid ranges (optional but recommended)
        final clampedX = x.clamp(0, previewSize.width).toDouble();
        final clampedY = y.clamp(0, previewSize.height).toDouble();
        final clampedWidth = width
            .clamp(0, previewSize.width - clampedX)
            .toDouble();
        final clampedHeight = height
            .clamp(0, previewSize.height - clampedY)
            .toDouble();

        detectionBoxes.add(
          DetectionBox(
            x: clampedX,
            y: clampedY,
            width: clampedWidth,
            height: clampedHeight,
          ),
        );
      }

      print('Valid detections: ${detectionBoxes.length}');
      return detectionBoxes;
    } catch (e) {
      print('Error capturing frame: $e');
      return [];
    }
  }

  Future<void> switchCamera() async {
    if (cameras.length < 2) {
      return;
    }

    setState(() {
      _isCameraInitialized = false;
    });

    _currentCameraIndex = (_currentCameraIndex + 1) % cameras.length;
    await initializeCamera(_currentCameraIndex);
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
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
                      maxWidth: MediaQuery.of(context).size.width * 0.9,
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: AspectRatio(
                      aspectRatio: _cameraController!.value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(_cameraController!),
                          CustomPaint(
                            painter: DetectionPainter(
                              _detections,
                              detectionResults: _detectionResults,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (cameras.length > 1)
                    Positioned(
                      bottom: 16,
                      child: FloatingActionButton(
                        mini: true,
                        onPressed: switchCamera,
                        tooltip: 'Switch Camera',
                        child: const Icon(Icons.flip_camera_ios),
                      ),
                    ),
                ],
              )
            else
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.6,
                child: const Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 20),
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
