import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../models/detection_box.dart';
import '../models/detection_result.dart';
import '../services/camera_service.dart';
import '../services/model_service.dart';
import '../services/detection_service.dart';
import '../widgets/camera_preview_widget.dart';

class HomeScreen extends StatefulWidget {
  final String title;
  final List<CameraDescription> cameras;

  const HomeScreen({
    super.key,
    required this.title,
    required this.cameras,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late ModelService _modelService;
  late CameraService _cameraService;
  late DetectionService _detectionService;

  int _counter = 0;
  bool _isCameraInitialized = false;
  List<DetectionBox> _detections = [];
  List<DetectionResult> _detectionResults = [];
  Size _originalImageSize = const Size(1, 1);
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    _modelService = ModelService();
    _cameraService = CameraService(widget.cameras);

    await _modelService.loadModel();
    await _initializeCamera();

    _detectionService = DetectionService(
      modelService: _modelService,
      cameraService: _cameraService,
    );

    _startDetectionStream();
  }

  Future<void> _initializeCamera() async {
    await _cameraService.initialize(_cameraService.currentCameraIndex);
    if (mounted) {
      setState(() {
        _isCameraInitialized = true;
      });
    }
  }

  void _startDetectionStream() {
    _cameraService.startImageStream((image) {
      if (!_isProcessing) {
        _runDetectionOnStream(image);
      }
    });
  }

  Future<void> _runDetectionOnStream(CameraImage image) async {
    if (_isProcessing) return;

    _isProcessing = true;

    try {
      final results = await _detectionService.processFrame(image);

      if (mounted) {
        setState(() {
          _detections = results.boxes;
          _detectionResults = results.results;
          _originalImageSize = Size(results.imageWidth, results.imageHeight);
        });
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _switchCamera() async {
    setState(() {
      _isCameraInitialized = false;
    });

    await _cameraService.switchCamera();

    if (mounted) {
      setState(() {
        _isCameraInitialized = true;
      });

      _startDetectionStream();
    }
  }

  @override
  void dispose() {
    _cameraService.dispose();
    _modelService.dispose();
    super.dispose();
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_isCameraInitialized && _cameraService.controller != null)
              CameraPreviewWidget(
                cameraController: _cameraService.controller!,
                detections: _detections,
                detectionResults: _detectionResults,
                originalImageSize: _originalImageSize,
                onSwitchCamera: _switchCamera,
                showSwitchButton: widget.cameras.length > 1,
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
      ),
    );
  }
}
