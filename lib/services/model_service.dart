import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:executorch_flutter/executorch_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as math;

import '../models/detection_result.dart';

class ModelService {
  late ExecuTorchModel model;

  Future<void> loadModel() async {
    final byteData = await rootBundle.load('assets/model.pte');
    final tempDir = await getTemporaryDirectory();

    final file = File('${tempDir.path}/model_v2.pte');

    if (await file.exists()) {
      await file.delete();
    }
    await file.writeAsBytes(byteData.buffer.asUint8List());

    print('[MODEL] Loading model from: ${file.path}');
    print('[MODEL] Model file size: ${await file.length()} bytes');

    model = await ExecuTorchModel.load(file.path);

    print('[MODEL] Model loaded successfully!');
  }

  Float32List prepareImageForModel(Uint8List imageBytes) {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('Failed to decode image');

    print('[PREPROCESSING] Original image: ${image.width}x${image.height}');

    img.Image resized = img.copyResize(image, width: 640, height: 640);

    print('[PREPROCESSING] Resized to: ${resized.width}x${resized.height}');

    if (resized.numChannels == 4) {
      resized = img.copyResize(resized, width: 640, height: 640);
    }

    const meanR = 0.485;
    const meanG = 0.456;
    const meanB = 0.406;
    const stdR = 0.229;
    const stdG = 0.224;
    const stdB = 0.225;

    final float32list = Float32List(1 * 3 * 640 * 640);

    int pixelIndex = 0;

    for (int y = 0; y < 640; y++) {
      for (int x = 0; x < 640; x++) {
        final pixel = resized.getPixel(x, y);
        float32list[pixelIndex++] = (pixel.r / 255.0 - meanR) / stdR;
      }
    }

    for (int y = 0; y < 640; y++) {
      for (int x = 0; x < 640; x++) {
        final pixel = resized.getPixel(x, y);
        float32list[pixelIndex++] = (pixel.g / 255.0 - meanG) / stdG;
      }
    }

    for (int y = 0; y < 640; y++) {
      for (int x = 0; x < 640; x++) {
        final pixel = resized.getPixel(x, y);
        float32list[pixelIndex++] = (pixel.b / 255.0 - meanB) / stdB;
      }
    }

    print('[PREPROCESSING] Sample tensor values (first 10):');
    for (int i = 0; i < math.min(10, float32list.length); i++) {
      print('  [$i] = ${float32list[i]}');
    }
    print(
      '[PREPROCESSING] Tensor min/max: ${float32list.reduce(math.min)} / ${float32list.reduce(math.max)}',
    );

    return float32list;
  }

  Future<List<TensorData>> runInference(Float32List processedImage) async {
    final Uint8List tensorBytes = processedImage.buffer.asUint8List();
    final inputTensor = TensorData(
      shape: [1, 3, 640, 640],
      dataType: TensorType.float32,
      data: tensorBytes,
    );

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

    return outputs;
  }

  Float32List boxCxcywhToXyxy(Float32List boxes, List<int> shape) {
    final numBoxes = shape[1];
    final result = Float32List(boxes.length);

    for (int i = 0; i < numBoxes; i++) {
      final offset = i * 4;
      final cx = boxes[offset + 0];
      final cy = boxes[offset + 1];
      final w = boxes[offset + 2];
      final h = boxes[offset + 3];

      result[offset + 0] = cx - w / 2;
      result[offset + 1] = cy - h / 2;
      result[offset + 2] = cx + w / 2;
      result[offset + 3] = cy + h / 2;
    }

    return result;
  }

  Float32List softmaxLastDim(Float32List data, List<int> shape) {
    final batch = shape[0];
    final numBoxes = shape[1];
    final numClasses = shape[2];

    final result = Float32List(data.length);

    for (int b = 0; b < batch; b++) {
      for (int i = 0; i < numBoxes; i++) {
        final offset = (b * numBoxes * numClasses) + (i * numClasses);

        double maxVal = data[offset];
        for (int c = 1; c < numClasses; c++) {
          maxVal = math.max(maxVal, data[offset + c]);
        }

        double sum = 0.0;
        for (int c = 0; c < numClasses; c++) {
          result[offset + c] = math.exp(data[offset + c] - maxVal);
          sum += result[offset + c];
        }

        for (int c = 0; c < numClasses; c++) {
          result[offset + c] /= sum;
        }
      }
    }

    return result;
  }

  List<Map<String, double>> maxLastDim(Float32List data, List<int> shape) {
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

    print(
      'First 16 bytes of box data (as Uint8): ${outBboxes.data.sublist(0, math.min(16, outBboxes.data.length))}',
    );

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

    final numBoxes = boxesShape[1];
    final numClasses = logitsShape[2];

    print('Processing $numBoxes boxes with $numClasses classes');
    print('Image dimensions: $imgWidth x $imgHeight');
    print('==================================================');

    print(
      'Raw box 0 (cx,cy,w,h): [${boxesData[0]}, ${boxesData[1]}, ${boxesData[2]}, ${boxesData[3]}]',
    );

    final xyxyBoxes = boxCxcywhToXyxy(boxesData, boxesShape);

    print('After cxcywh->xyxy conversion (normalized 0-1):');
    print(
      '  Box 0: [${xyxyBoxes[0]}, ${xyxyBoxes[1]}, ${xyxyBoxes[2]}, ${xyxyBoxes[3]}]',
    );
    print(
      '  Width: ${xyxyBoxes[2] - xyxyBoxes[0]}, Height: ${xyxyBoxes[3] - xyxyBoxes[1]}',
    );

    final scaledBoxes = Float32List(xyxyBoxes.length);
    for (int i = 0; i < numBoxes; i++) {
      final offset = i * 4;
      scaledBoxes[offset + 0] = xyxyBoxes[offset + 0] * imgWidth;
      scaledBoxes[offset + 1] = xyxyBoxes[offset + 1] * imgHeight;
      scaledBoxes[offset + 2] = xyxyBoxes[offset + 2] * imgWidth;
      scaledBoxes[offset + 3] = xyxyBoxes[offset + 3] * imgHeight;
    }

    print('After scaling to image dimensions:');
    print(
      '  Box 0: [${scaledBoxes[0]}, ${scaledBoxes[1]}, ${scaledBoxes[2]}, ${scaledBoxes[3]}]',
    );
    print(
      '  Width: ${scaledBoxes[2] - scaledBoxes[0]}, Height: ${scaledBoxes[3] - scaledBoxes[1]}',
    );

    final softmaxLogits = softmaxLastDim(logitsData, logitsShape);

    final classProbsPerBox = <List<double>>[];
    for (int i = 0; i < numBoxes; i++) {
      final offset = i * numClasses;
      final probs = <double>[];
      for (int c = 0; c < numClasses - 1; c++) {
        probs.add(softmaxLogits[offset + c]);
      }
      classProbsPerBox.add(probs);
    }

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

  void dispose() {
    model.dispose();
  }
}
