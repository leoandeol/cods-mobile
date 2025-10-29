import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../models/detection_box.dart';
import '../models/detection_result.dart';
import '../painters/detection_painter.dart';

class CameraPreviewWidget extends StatelessWidget {
  final CameraController cameraController;
  final List<DetectionBox> detections;
  final List<DetectionResult> detectionResults;
  final Size originalImageSize;
  final VoidCallback? onSwitchCamera;
  final bool showSwitchButton;

  const CameraPreviewWidget({
    super.key,
    required this.cameraController,
    required this.detections,
    required this.detectionResults,
    required this.originalImageSize,
    this.onSwitchCamera,
    this.showSwitchButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
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
            aspectRatio: cameraController.value.aspectRatio,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.scale(
                      scaleX: -1,
                      child: CameraPreview(cameraController),
                    ),
                    CustomPaint(
                      painter: DetectionPainter(
                        detections,
                        detectionResults: detectionResults,
                        originalImageSize: originalImageSize,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        if (showSwitchButton && onSwitchCamera != null)
          Positioned(
            bottom: 16,
            child: FloatingActionButton(
              mini: true,
              onPressed: onSwitchCamera,
              tooltip: 'Switch Camera',
              child: const Icon(Icons.flip_camera_ios),
            ),
          ),
      ],
    );
  }
}
