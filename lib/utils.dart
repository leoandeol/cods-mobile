import 'dart:typed_data';
import 'dart:math' as math;

import 'package:executorch_flutter/executorch_flutter.dart';

class TensorHelper {
  final Float32List data;
  final List<int> shape;

  TensorHelper(this.data, this.shape) {
    // Verify shape matches data length
    final totalElements = shape.reduce((a, b) => a * b);
    if (totalElements != data.length) {
      throw Exception('Shape $shape does not match data length ${data.length}');
    }
  }

  // Create from TensorData
  factory TensorHelper.fromTensorData(TensorData tensorData) {
    final float32Data = tensorData.data.buffer.asFloat32List();
    // Filter out nulls from shape and convert to non-nullable list
    final cleanShape = tensorData.shape
        .where((e) => e != null)
        .map((e) => e!)
        .toList();
    return TensorHelper(float32Data, cleanShape);
  }

  // Get number of dimensions
  int get ndim => shape.length;

  // Get total number of elements
  int get size => data.length;

  // Calculate strides for indexing
  List<int> get strides {
    final strides = List<int>.filled(shape.length, 1);
    for (int i = shape.length - 2; i >= 0; i--) {
      strides[i] = strides[i + 1] * shape[i + 1];
    }
    return strides;
  }

  // Get flat index from multi-dimensional indices
  int _flatIndex(List<int> indices) {
    if (indices.length != shape.length) {
      throw Exception('Number of indices must match number of dimensions');
    }

    int flatIdx = 0;
    final tensorStrides = strides;

    for (int i = 0; i < indices.length; i++) {
      if (indices[i] < 0 || indices[i] >= shape[i]) {
        throw Exception(
          'Index ${indices[i]} out of bounds for axis $i with size ${shape[i]}',
        );
      }
      flatIdx += indices[i] * tensorStrides[i];
    }

    return flatIdx;
  }

  // Get element at multi-dimensional index
  // Example: tensor.at([0, 1, 2, 3])
  double at(List<int> indices) {
    return data[_flatIndex(indices)];
  }

  // Set element at multi-dimensional index
  void setAt(List<int> indices, double value) {
    data[_flatIndex(indices)] = value;
  }

  // Slice tensor (similar to numpy slicing)
  // Example: tensor.slice([0, null, null, null]) gets first batch
  TensorHelper slice(List<dynamic> sliceSpec) {
    // sliceSpec can contain:
    // - int: single index
    // - null: all indices (equivalent to :)
    // - List<int> [start, end]: range (equivalent to start:end)

    List<int> newShape = [];
    List<int> startIndices = [];

    for (int i = 0; i < sliceSpec.length; i++) {
      if (sliceSpec[i] == null) {
        newShape.add(shape[i]);
        startIndices.add(0);
      } else if (sliceSpec[i] is int) {
        startIndices.add(sliceSpec[i] as int);
      } else if (sliceSpec[i] is List<int>) {
        final range = sliceSpec[i] as List<int>;
        newShape.add(range[1] - range[0]);
        startIndices.add(range[0]);
      }
    }

    // Calculate new data
    final newSize = newShape.reduce((a, b) => a * b);
    final newData = Float32List(newSize);

    // Copy data (simplified - for full implementation would need recursive copying)
    // This is a basic implementation
    int newIdx = 0;
    _copySlice(startIndices, newShape, newData, newIdx, 0, []);

    return TensorHelper(newData, newShape);
  }

  void _copySlice(
    List<int> startIndices,
    List<int> sizes,
    Float32List newData,
    int newIdx,
    int dim,
    List<int> currentIndices,
  ) {
    if (dim == sizes.length) {
      final sourceIndices = List<int>.generate(
        startIndices.length,
        (i) => i < currentIndices.length
            ? startIndices[i] + currentIndices[i]
            : startIndices[i],
      );
      newData[newIdx] = data[_flatIndex(sourceIndices)];
      return;
    }

    for (int i = 0; i < sizes[dim]; i++) {
      _copySlice(startIndices, sizes, newData, newIdx + i, dim + 1, [
        ...currentIndices,
        i,
      ]);
    }
  }

  // Squeeze - remove dimensions of size 1
  // Example: [1, 3, 224, 224] -> [3, 224, 224]
  TensorHelper squeeze([List<int>? axes]) {
    List<int> newShape = [];

    for (int i = 0; i < shape.length; i++) {
      if (axes == null) {
        if (shape[i] != 1) newShape.add(shape[i]);
      } else {
        if (!axes.contains(i) || shape[i] != 1) {
          newShape.add(shape[i]);
        }
      }
    }

    return TensorHelper(data, newShape);
  }

  // Reshape tensor
  TensorHelper reshape(List<int> newShape) {
    final newSize = newShape.reduce((a, b) => a * b);
    if (newSize != size) {
      throw Exception('Cannot reshape: size mismatch');
    }
    return TensorHelper(data, newShape);
  }

  // Transpose (swap two axes)
  TensorHelper transpose([int axis1 = 0, int axis2 = 1]) {
    if (axis1 >= shape.length || axis2 >= shape.length) {
      throw Exception('Axis out of bounds');
    }

    final newShape = List<int>.from(shape);
    newShape[axis1] = shape[axis2];
    newShape[axis2] = shape[axis1];

    final newData = Float32List(size);

    // Transpose data
    _transposeRecursive(List.filled(shape.length, 0), axis1, axis2, newData, 0);

    return TensorHelper(newData, newShape);
  }

  void _transposeRecursive(
    List<int> indices,
    int axis1,
    int axis2,
    Float32List newData,
    int currentDim,
  ) {
    if (currentDim == shape.length) {
      final newIndices = List<int>.from(indices);
      final temp = newIndices[axis1];
      newIndices[axis1] = newIndices[axis2];
      newIndices[axis2] = temp;

      newData[_flatIndex(newIndices)] = data[_flatIndex(indices)];
      return;
    }

    for (int i = 0; i < shape[currentDim]; i++) {
      indices[currentDim] = i;
      _transposeRecursive(indices, axis1, axis2, newData, currentDim + 1);
    }
  }

  // Argmax - get index of maximum value along axis
  List<int> argmax({int? axis}) {
    if (axis == null) {
      // Global argmax
      int maxIdx = 0;
      double maxVal = data[0];
      for (int i = 1; i < data.length; i++) {
        if (data[i] > maxVal) {
          maxVal = data[i];
          maxIdx = i;
        }
      }
      return [maxIdx];
    }

    // Argmax along specific axis
    // This is simplified - full implementation would be more complex
    throw UnimplementedError('Argmax along axis not yet implemented');
  }

  // Max value
  double max() => data.reduce(math.max);

  // Min value
  double min() => data.reduce(math.min);

  // Mean value
  double mean() => data.reduce((a, b) => a + b) / data.length;

  // Apply function element-wise
  TensorHelper map(double Function(double) fn) {
    final newData = Float32List(size);
    for (int i = 0; i < size; i++) {
      newData[i] = fn(data[i]);
    }
    return TensorHelper(newData, shape);
  }

  // Apply softmax
  TensorHelper softmax({int axis = -1}) {
    if (axis == -1) axis = shape.length - 1;

    // For simplicity, assuming last dimension
    final newData = Float32List(size);

    if (axis == shape.length - 1) {
      final lastDim = shape[axis];
      final numGroups = size ~/ lastDim;

      for (int g = 0; g < numGroups; g++) {
        final offset = g * lastDim;

        // Find max for numerical stability
        double maxVal = data[offset];
        for (int i = 1; i < lastDim; i++) {
          maxVal = math.max(maxVal, data[offset + i]);
        }

        // Compute exp and sum
        double sum = 0.0;
        for (int i = 0; i < lastDim; i++) {
          newData[offset + i] = math.exp(data[offset + i] - maxVal);
          sum += newData[offset + i];
        }

        // Normalize
        for (int i = 0; i < lastDim; i++) {
          newData[offset + i] /= sum;
        }
      }
    }

    return TensorHelper(newData, shape);
  }

  // Convert back to TensorData
  TensorData toTensorData({
    TensorType dataType = TensorType.float32,
    String? name,
  }) {
    return TensorData(
      shape: shape,
      dataType: dataType,
      data: data.buffer.asUint8List(),
      name: name,
    );
  }

  // Print tensor info
  @override
  String toString() {
    return 'TensorHelper(shape: $shape, size: $size, dtype: float32)';
  }

  // Print first N values
  String preview([int n = 10]) {
    final previewData = data.take(math.min(n, size)).toList();
    return 'TensorHelper(shape: $shape)\n  data: $previewData...';
  }
}
