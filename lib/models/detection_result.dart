class DetectionResult {
  final double x1, y1, x2, y2;
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
