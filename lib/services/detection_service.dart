import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import '../models/detection_box.dart';
import '../models/detection_result.dart';
import 'camera_service.dart';
import 'model_service.dart';

class DetectionService {
  final ModelService modelService;
  final CameraService cameraService;

  DetectionService({
    required this.modelService,
    required this.cameraService,
  });

  Future<DetectionResults> processFrame(CameraImage image) async {
    try {
      final Uint8List imageBytes = cameraService.convertYUV420ToImage(image);

      final originalWidth = image.width.toDouble();
      final originalHeight = image.height.toDouble();

      print('\n========== PROCESSING FRAME FROM STREAM ==========');
      print('Stream image size: $originalWidth x $originalHeight');

      final processedImage = modelService.prepareImageForModel(imageBytes);
      final outputs = await modelService.runInference(processedImage);

      if (outputs.length < 2) {
        return DetectionResults([], [], originalWidth, originalHeight);
      }

      final outputClassif = outputs[0];
      final outputBoxes = outputs[1];

      final detections = modelService.postprocess(
        outputClassif,
        outputBoxes,
        originalWidth,
        originalHeight,
      );

      final detectionBoxes = <DetectionBox>[];

      print(
        '\nConverting ${detections.length} DetectionResults to DetectionBoxes:',
      );
      int boxNum = 0;
      for (var det in detections) {
        if (det.x1.isNaN || det.y1.isNaN || det.x2.isNaN || det.y2.isNaN) {
          continue;
        }

        if (det.x1.isInfinite ||
            det.y1.isInfinite ||
            det.x2.isInfinite ||
            det.y2.isInfinite) {
          continue;
        }

        final box = DetectionBox(
          x: det.x1,
          y: det.y1,
          width: det.x2 - det.x1,
          height: det.y2 - det.y1,
        );

        if (boxNum < 3) {
          print(
            '  Box $boxNum: x=${box.x}, y=${box.y}, w=${box.width}, h=${box.height}',
          );
        }
        boxNum++;

        detectionBoxes.add(box);
      }

      print('Created ${detectionBoxes.length} DetectionBoxes');
      print('==================================================\n');

      return DetectionResults(
        detectionBoxes,
        detections,
        originalWidth,
        originalHeight,
      );
    } catch (e) {
      print('Error processing stream frame: $e');
      return DetectionResults([], [], 1, 1);
    }
  }
}

class DetectionResults {
  final List<DetectionBox> boxes;
  final List<DetectionResult> results;
  final double imageWidth;
  final double imageHeight;

  DetectionResults(
    this.boxes,
    this.results,
    this.imageWidth,
    this.imageHeight,
  );
}
