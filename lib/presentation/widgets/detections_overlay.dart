// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/detection_view_model.dart';
import '../controllers/camera_inference_controller.dart';

/// Paints a single, centralized pipeline of detection results on top of the camera.
class DetectionsOverlay extends StatelessWidget {
  const DetectionsOverlay({
    super.key,
    required this.controller,
  });

  final CameraInferenceController controller;

  @override
  Widget build(BuildContext context) {
    final detections = controller.visibleDetections;
    if (detections.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _DetectionsPainter(detections: detections),
        ),
      ),
    );
  }
}

class _DetectionsPainter extends CustomPainter {
  _DetectionsPainter({required this.detections});

  final List<DetectionViewModel> detections;

  final Paint _boxPaint = Paint()
    ..color = Colors.deepPurpleAccent
    ..strokeWidth = 2.4
    ..style = PaintingStyle.stroke;

  final Paint _labelBackground = Paint()
    ..color = Colors.black.withOpacity(0.65)
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      final rect = _mapRectToCanvas(detection, size);
      if (rect.isEmpty) continue;

      canvas.drawRect(rect, _boxPaint);
      _paintLabel(canvas, rect, detection, size);
    }
  }

  void _paintLabel(
    Canvas canvas,
    Rect rect,
    DetectionViewModel detection,
    Size canvasSize,
  ) {
    final confidence = (detection.confidence * 100).clamp(0, 100).toStringAsFixed(1);
    final textSpan = TextSpan(
      text: '${detection.label} $confidence%',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: canvasSize.width * 0.9);

    final padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    final labelWidth = textPainter.width + padding.horizontal;
    final labelHeight = textPainter.height + padding.vertical;

    var labelLeft = rect.left;
    var labelTop = rect.top - labelHeight;

    if (labelLeft + labelWidth > canvasSize.width) {
      labelLeft = canvasSize.width - labelWidth;
    }
    if (labelTop < 0) {
      labelTop = rect.top;
    }

    final labelRect = Rect.fromLTWH(
      labelLeft,
      labelTop,
      labelWidth,
      labelHeight,
    );

    final rRect = RRect.fromRectAndRadius(labelRect, const Radius.circular(6));
    canvas.drawRRect(rRect, _labelBackground);

    final textOffset = Offset(
      labelRect.left + padding.left,
      labelRect.top + padding.top,
    );
    textPainter.paint(canvas, textOffset);
  }

  Rect _mapRectToCanvas(DetectionViewModel detection, Size canvasSize) {
    final source = detection.sourceSize;
    if (source.width <= 0 || source.height <= 0) {
      return Rect.zero;
    }

    final fittedSizes = applyBoxFit(BoxFit.contain, source, canvasSize);
    final destination = fittedSizes.destination;

    final scaleX = destination.width / source.width;
    final scaleY = destination.height / source.height;
    final offsetX = (canvasSize.width - destination.width) / 2;
    final offsetY = (canvasSize.height - destination.height) / 2;

    final box = detection.boundingBox;
    final left = offsetX + box.left * scaleX;
    final top = offsetY + box.top * scaleY;
    final right = offsetX + box.right * scaleX;
    final bottom = offsetY + box.bottom * scaleY;

    final mapped = Rect.fromLTRB(left, top, right, bottom);

    if (mapped.width <= 1 || mapped.height <= 1) {
      return Rect.zero;
    }

    final rounded = Rect.fromLTRB(
      mapped.left.roundToDouble(),
      mapped.top.roundToDouble(),
      mapped.right.roundToDouble(),
      mapped.bottom.roundToDouble(),
    );

    final clamped = Rect.fromLTRB(
      math.max(0.0, rounded.left),
      math.max(0.0, rounded.top),
      math.min(canvasSize.width, rounded.right),
      math.min(canvasSize.height, rounded.bottom),
    );

    if (clamped.width <= 0 || clamped.height <= 0) {
      return Rect.zero;
    }
    return clamped;
  }

  @override
  bool shouldRepaint(covariant _DetectionsPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
