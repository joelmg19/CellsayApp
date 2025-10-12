// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:ui';

import 'package:ultralytics_yolo/models/yolo_result.dart';

/// Lightweight view model used to render filtered detections on the canvas.
class DetectionViewModel {
  const DetectionViewModel({
    required this.original,
    required this.boundingBox,
    required this.sourceSize,
    required this.label,
    required this.confidence,
  });

  /// Original YOLO result kept for downstream consumers (voice, etc.).
  final YOLOResult original;

  /// Bounding box expressed in the source image coordinate space.
  final Rect boundingBox;

  /// Size of the image tensor that produced [boundingBox].
  final Size sourceSize;

  /// Human-readable label associated with the detection.
  final String label;

  /// Confidence score in the 0..1 range.
  final double confidence;

  /// Bounding box expressed as normalized coordinates.
  Rect get normalizedBox {
    final width = sourceSize.width <= 0 ? 1.0 : sourceSize.width;
    final height = sourceSize.height <= 0 ? 1.0 : sourceSize.height;
    return Rect.fromLTRB(
      boundingBox.left / width,
      boundingBox.top / height,
      boundingBox.right / width,
      boundingBox.bottom / height,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DetectionViewModel &&
        other.label == label &&
        (other.confidence - confidence).abs() < 1e-3 &&
        other.boundingBox == boundingBox &&
        other.sourceSize == sourceSize;
  }

  @override
  int get hashCode => Object.hash(label, confidence, boundingBox, sourceSize);
}
