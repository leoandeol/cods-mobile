import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/detection_box.dart';
import '../models/detection_result.dart';
import '../models/coco_classes.dart';

class DetectionPainter extends CustomPainter {
  final List<DetectionBox> detections;
  final List<DetectionResult>? detectionResults;
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

    print('\n########## DETECTION PAINTER ##########');
    print('Canvas size: ${size.width} x ${size.height}');
    print(
      'Original image size: ${originalImageSize.width} x ${originalImageSize.height}',
    );
    print('Number of detections: ${detections.length}');

    final isCanvasPortrait = size.height > size.width;
    final isImageLandscape = originalImageSize.width > originalImageSize.height;
    final needsRotation = isCanvasPortrait && isImageLandscape;

    print(
      'Canvas portrait: $isCanvasPortrait, Image landscape: $isImageLandscape, Needs rotation: $needsRotation',
    );

    for (int i = 0; i < detections.length; i++) {
      final detection = detections[i];

      if (i < 3) {
        print('\n--- Processing detection $i ---');
        print(
          'Input box: x=${detection.x}, y=${detection.y}, w=${detection.width}, h=${detection.height}',
        );
      }

      double boxX, boxY, boxWidth, boxHeight;

      if (needsRotation) {
        boxX = detection.y;
        boxY = originalImageSize.width - (detection.x + detection.width);
        boxWidth = detection.height;
        boxHeight = detection.width;

        if (i < 3)
          print('After rotation: x=$boxX, y=$boxY, w=$boxWidth, h=$boxHeight');

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
