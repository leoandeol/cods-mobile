import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class CameraService {
  CameraController? _controller;
  int _currentCameraIndex = 0;
  final List<CameraDescription> cameras;

  CameraService(this.cameras);

  CameraController? get controller => _controller;
  int get currentCameraIndex => _currentCameraIndex;
  bool get isInitialized =>
      _controller != null && _controller!.value.isInitialized;

  Future<void> initialize(int cameraIndex) async {
    if (cameras.isEmpty) {
      return;
    }

    await _controller?.dispose();

    _currentCameraIndex = cameraIndex;
    _controller = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();
  }

  Future<void> switchCamera() async {
    if (cameras.length < 2) {
      return;
    }

    await _controller?.stopImageStream();
    _currentCameraIndex = (_currentCameraIndex + 1) % cameras.length;
    await initialize(_currentCameraIndex);
  }

  void startImageStream(Function(CameraImage) onImage) {
    _controller?.startImageStream(onImage);
  }

  Future<void> stopImageStream() async {
    await _controller?.stopImageStream();
  }

  Uint8List convertYUV420ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

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

        int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .round()
            .clamp(0, 255);
        int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

        imgLib.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    return Uint8List.fromList(img.encodeJpg(imgLib));
  }

  Future<void> dispose() async {
    await _controller?.stopImageStream().catchError((_) {});
    await _controller?.dispose();
  }
}
