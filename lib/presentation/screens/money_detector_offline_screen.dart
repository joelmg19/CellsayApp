import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ultralytics_yolo/models/yolo_result.dart';
import 'package:ultralytics_yolo/models/yolo_task.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

import '../../core/vision/detection_geometry.dart';

class MoneyDetectorOfflineScreen extends StatefulWidget {
  const MoneyDetectorOfflineScreen({super.key});

  @override
  State<MoneyDetectorOfflineScreen> createState() =>
      _MoneyDetectorOfflineScreenState();
}

class _MoneyDetectorOfflineScreenState
    extends State<MoneyDetectorOfflineScreen> {
  static const String _assetModelPath = 'assets/models/best_float16money.tflite';

  final FlutterTts _tts = FlutterTts();
  final YOLOViewController _yoloController = YOLOViewController();
  final Duration _voiceCooldown = const Duration(seconds: 3);
  final Map<String, String> _labelToSpeech = {
    'billete_1000': 'Billete de mil pesos chilenos',
    'billete_2000': 'Billete de dos mil pesos chilenos',
    'billete_5000': 'Billete de cinco mil pesos chilenos',
    'billete_10000': 'Billete de diez mil pesos chilenos',
    'billete_20000': 'Billete de veinte mil pesos chilenos',
  };

  List<YOLOResult> _detections = const [];
  String? _modelPath;
  bool _isPreparingModel = true;
  String? _errorMessage;
  DateTime _lastVoice = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _initTts();
    await _prepareModel();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('es-ES');
    await _tts.setSpeechRate(0.9);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> _prepareModel() async {
    setState(() {
      _isPreparingModel = true;
      _errorMessage = null;
    });
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = p.join(dir.path, 'best_float16money.tflite');
      final modelFile = File(filePath);
      if (!await modelFile.exists()) {
        final data = await rootBundle.load(_assetModelPath);
        final buffer = data.buffer.asUint8List();
        await modelFile.writeAsBytes(buffer, flush: true);
      }
      if (!mounted) return;
      setState(() {
        _modelPath = filePath;
        _isPreparingModel = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No se pudo preparar el modelo offline.';
        _isPreparingModel = false;
      });
    }
  }

  void _handleStreamingData(Map<String, dynamic> data) {
    if (!mounted) return;
    final detections = <YOLOResult>[];
    final rawDetections = data['detections'];
    if (rawDetections is List) {
      for (final detection in rawDetections) {
        if (detection is Map) {
          try {
            detections.add(
              YOLOResult.fromMap(
                detection.map((key, value) => MapEntry('$key', value)),
              ),
            );
          } catch (_) {
            continue;
          }
        }
      }
    }
    setState(() {
      _detections = detections;
    });
    unawaited(_announceDetection(detections));
  }

  Future<void> _announceDetection(List<YOLOResult> detections) async {
    if (detections.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastVoice) < _voiceCooldown) return;

    YOLOResult? best;
    double bestConfidence = 0;
    for (final result in detections) {
      final confidence = extractConfidence(result) ?? 0;
      if (confidence > bestConfidence) {
        bestConfidence = confidence;
        best = result;
      }
    }
    if (best == null) return;

    final label = extractLabel(best);
    final phrase = _labelToSpeech[label] ?? 'Billete detectado';
    await _tts.speak(phrase);
    _lastVoice = DateTime.now();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dinero sin Internet'),
        actions: [
          IconButton(
            tooltip: 'Reintentar',
            onPressed: _isPreparingModel ? null : _prepareModel,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    if (_isPreparingModel) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Preparando modelo offline...'),
          ],
        ),
      );
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_rounded, size: 52, color: Colors.amber.shade700),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _prepareModel,
                icon: const Icon(Icons.refresh),
                label: const Text('Intentar de nuevo'),
              ),
            ],
          ),
        ),
      );
    }
    if (_modelPath == null) {
      return const Center(child: Text('No se encontró el modelo.'));
    }

    return Stack(
      children: [
        Positioned.fill(
          child: YOLOView(
            controller: _yoloController,
            modelPath: _modelPath!,
            task: YOLOTask.detect,
            streamingConfig: const YOLOStreamingConfig.custom(
              includeDetections: true,
              includeOriginalImage: false,
              includeProcessingTimeMs: false,
              includeFps: false,
              includeClassifications: false,
            ),
            onStreamingData: _handleStreamingData,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _MoneyDetectionsPainter(_detections),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: _DetectionsPanel(detections: _detections),
        ),
      ],
    );
  }
}

class _MoneyDetectionsPainter extends CustomPainter {
  _MoneyDetectionsPainter(this.detections);

  final List<YOLOResult> detections;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final textStyle = TextStyle(
      color: Colors.greenAccent.shade100,
      fontSize: 14,
      background: Paint()
        ..color = Colors.black.withOpacity(0.55)
        ..style = PaintingStyle.fill,
    );

    for (final detection in detections) {
      Rect? rect = detection.normalizedBox;
      rect ??= extractBoundingBox(detection);
      if (rect == null) continue;

      if (rect.right > 1 || rect.bottom > 1) {
        final imageWidth = extractImageWidthPx(detection);
        final imageHeight = extractImageHeightPx(detection);
        if (imageWidth != null && imageWidth > 0 && imageHeight != null && imageHeight > 0) {
          rect = Rect.fromLTRB(
            rect.left / imageWidth,
            rect.top / imageHeight,
            rect.right / imageWidth,
            rect.bottom / imageHeight,
          );
        }
      }

      final scaledRect = Rect.fromLTRB(
        rect.left.clamp(0.0, 1.0) * size.width,
        rect.top.clamp(0.0, 1.0) * size.height,
        rect.right.clamp(0.0, 1.0) * size.width,
        rect.bottom.clamp(0.0, 1.0) * size.height,
      );

      canvas.drawRect(scaledRect, paint);

      final label = extractLabel(detection);
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(scaledRect.left, scaledRect.top - tp.height));
    }
  }

  @override
  bool shouldRepaint(covariant _MoneyDetectionsPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}

class _DetectionsPanel extends StatelessWidget {
  const _DetectionsPanel({required this.detections});

  final List<YOLOResult> detections;

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Sin billetes detectados. Apunta a un billete y espera la indicación por voz.',
          style: TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
    }

    final entries = detections.take(3).map((result) {
      final label = extractLabel(result);
      final confidence = (extractConfidence(result) ?? 0) * 100;
      return '$label • ${confidence.toStringAsFixed(1)}%';
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Detecciones',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                entry,
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
