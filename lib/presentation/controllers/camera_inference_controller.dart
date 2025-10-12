// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/models/yolo_result.dart';
import 'package:ultralytics_yolo/utils/error_handler.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import '../../models/models.dart';
import '../../services/model_manager.dart';
import '../../services/voice_announcer.dart';

/// Controller that manages the state and business logic for camera inference
class CameraInferenceController extends ChangeNotifier {
  // Detection state
  int _detectionCount = 0;
  double _currentFps = 0.0;
  int _frameCount = 0;
  DateTime _lastFpsUpdate = DateTime.now();
  List<DetectionViewModel> _visibleDetections = const <DetectionViewModel>[];

  static const double _nmsIoUThreshold = 0.55; // ≈0.5–0.6 as requested.

  // Threshold state
  double _confidenceThreshold = 0.5;
  double _iouThreshold = 0.45;
  int _numItemsThreshold = 30;
  SliderType _activeSlider = SliderType.none;

  // Model state
  ModelType _selectedModel = ModelType.detect;
  bool _isModelLoading = false;
  String? _modelPath;
  String _loadingMessage = '';
  double _downloadProgress = 0.0;

  // Camera state
  double _currentZoomLevel = 1.0;
  bool _isFrontCamera = false;
  bool _isVoiceEnabled = true;

  // Controllers
  final _yoloController = YOLOViewController();
  late final ModelManager _modelManager;
  final VoiceAnnouncer _voiceAnnouncer = VoiceAnnouncer();

  // Performance optimization
  bool _isDisposed = false;
  Future<void>? _loadingFuture;

  // Getters
  int get detectionCount => _detectionCount;
  double get currentFps => _currentFps;
  List<DetectionViewModel> get visibleDetections => _visibleDetections;
  double get confidenceThreshold => _confidenceThreshold;
  double get iouThreshold => _iouThreshold;
  int get numItemsThreshold => _numItemsThreshold;
  SliderType get activeSlider => _activeSlider;
  ModelType get selectedModel => _selectedModel;
  bool get isModelLoading => _isModelLoading;
  String? get modelPath => _modelPath;
  String get loadingMessage => _loadingMessage;
  double get downloadProgress => _downloadProgress;
  double get currentZoomLevel => _currentZoomLevel;
  bool get isFrontCamera => _isFrontCamera;
  bool get isVoiceEnabled => _isVoiceEnabled;
  YOLOViewController get yoloController => _yoloController;

  CameraInferenceController() {
    _modelManager = ModelManager(
      onDownloadProgress: (progress) {
        _downloadProgress = progress;
        notifyListeners();
      },
      onStatusUpdate: (message) {
        _loadingMessage = message;
        notifyListeners();
      },
    );
  }

  /// Initialize the controller
  Future<void> initialize() async {
    await _loadModelForPlatform();
    _yoloController.setThresholds(
      confidenceThreshold: _confidenceThreshold,
      iouThreshold: _iouThreshold,
      numItemsThreshold: _numItemsThreshold,
    );
  }

  /// Handle detection results and calculate FPS
  void onDetectionResults(List<YOLOResult> results) {
    if (_isDisposed) return;

    _frameCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastFpsUpdate).inMilliseconds;

    if (elapsed >= 1000) {
      _currentFps = _frameCount * 1000 / elapsed;
      _frameCount = 0;
      _lastFpsUpdate = now;
    }

    final processedDetections = _prepareDetections(results);
    var shouldNotify = false;

    if (!_listEqualsDetections(_visibleDetections, processedDetections)) {
      _visibleDetections = processedDetections;
      shouldNotify = true;
    }

    final filteredCount = processedDetections.length;
    if (_detectionCount != filteredCount) {
      _detectionCount = filteredCount;
      shouldNotify = true;
    }

    if (shouldNotify) {
      notifyListeners();
    }

    unawaited(
      _voiceAnnouncer.processDetections(
        processedDetections,
        isVoiceEnabled: _isVoiceEnabled,
      ),
    );
  }

  List<DetectionViewModel> _prepareDetections(List<YOLOResult> results) {
    if (results.isEmpty) {
      return const <DetectionViewModel>[];
    }

    final prepared = <DetectionViewModel>[];

    for (final result in results) {
      final rect = _extractRect(result);
      final sourceSize = _extractSourceSize(result);
      if (rect == null || sourceSize == null) {
        continue;
      }

      final denormalized = _denormalizeRect(rect, sourceSize);
      final clamped = _clampRectToSource(denormalized, sourceSize);
      if (clamped.width <= 0 || clamped.height <= 0) {
        continue;
      }

      prepared.add(
        DetectionViewModel(
          original: result,
          boundingBox: clamped,
          sourceSize: sourceSize,
          label: _extractLabel(result),
          confidence: _extractConfidence(result),
        ),
      );
    }

    if (prepared.length <= 1) {
      return List<DetectionViewModel>.unmodifiable(prepared);
    }

    final filtered = _applyNms(prepared, threshold: _nmsIoUThreshold);
    final deduplicated = _mergeNearDuplicates(filtered);
    return List<DetectionViewModel>.unmodifiable(deduplicated);
  }

  List<DetectionViewModel> _applyNms(
    List<DetectionViewModel> detections, {
    required double threshold,
  }) {
    if (detections.length <= 1) {
      return detections;
    }

    final sorted = List<DetectionViewModel>.of(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <DetectionViewModel>[];
    final suppressed = List<bool>.filled(sorted.length, false);

    for (var i = 0; i < sorted.length; i++) {
      if (suppressed[i]) continue;
      final current = sorted[i];
      kept.add(current);

      for (var j = i + 1; j < sorted.length; j++) {
        if (suppressed[j]) continue;
        final overlap = _computeIoU(
          current.normalizedBox,
          sorted[j].normalizedBox,
        );
        if (overlap >= threshold) {
          suppressed[j] = true;
        }
      }
    }

    return kept;
  }

  List<DetectionViewModel> _mergeNearDuplicates(
    List<DetectionViewModel> detections,
  ) {
    if (detections.length <= 1) {
      return detections;
    }

    final result = <DetectionViewModel>[];

    for (final detection in detections) {
      final existingIndex = result.indexWhere(
        (other) => _isDuplicateDetection(other, detection),
      );

      if (existingIndex == -1) {
        result.add(detection);
      } else if (detection.confidence > result[existingIndex].confidence) {
        result[existingIndex] = detection;
      }
    }

    return result;
  }

  bool _isDuplicateDetection(
    DetectionViewModel a,
    DetectionViewModel b,
  ) {
    if (identical(a, b)) return true;
    if (a.label != b.label) return false;
    if (a.sourceSize.width <= 0 || a.sourceSize.height <= 0) return false;
    if (b.sourceSize.width <= 0 || b.sourceSize.height <= 0) return false;

    final centerA = Offset(
      a.boundingBox.center.dx / a.sourceSize.width,
      a.boundingBox.center.dy / a.sourceSize.height,
    );
    final centerB = Offset(
      b.boundingBox.center.dx / b.sourceSize.width,
      b.boundingBox.center.dy / b.sourceSize.height,
    );
    final centerDistance = (centerA - centerB).distance;

    if (centerDistance > 0.045) {
      return false;
    }

    final areaA = (a.boundingBox.width / a.sourceSize.width).abs() *
        (a.boundingBox.height / a.sourceSize.height).abs();
    final areaB = (b.boundingBox.width / b.sourceSize.width).abs() *
        (b.boundingBox.height / b.sourceSize.height).abs();
    final areaDifference = (areaA - areaB).abs();

    final overlap = _computeIoU(a.normalizedBox, b.normalizedBox);

    return overlap >= 0.4 || (centerDistance <= 0.02 && areaDifference <= 0.06);
  }

  double _computeIoU(Rect a, Rect b) {
    final left = math.max(0.0, math.max(a.left, b.left));
    final top = math.max(0.0, math.max(a.top, b.top));
    final right = math.min(1.0, math.min(a.right, b.right));
    final bottom = math.min(1.0, math.min(a.bottom, b.bottom));

    final width = math.max(0.0, right - left);
    final height = math.max(0.0, bottom - top);
    final intersection = width * height;

    if (intersection <= 0) {
      return 0.0;
    }

    final areaA = math.max(0.0, a.width) * math.max(0.0, a.height);
    final areaB = math.max(0.0, b.width) * math.max(0.0, b.height);
    final union = areaA + areaB - intersection;
    if (union <= 0) {
      return 0.0;
    }
    return intersection / union;
  }

  Rect? _extractRect(YOLOResult result) {
    final dynamic dynamicResult = result;
    Rect? rect;
    rect ??= _rectFromDynamic(() => dynamicResult.boundingBox);
    rect ??= _rectFromDynamic(() => dynamicResult.box);
    rect ??= _rectFromDynamic(() => dynamicResult.rect);
    rect ??= _rectFromDynamic(() => dynamicResult.bbox);
    return rect;
  }

  Rect? _rectFromDynamic(dynamic Function() getter) {
    try {
      return _rectFromValue(getter());
    } catch (_) {
      return null;
    }
  }

  Rect? _rectFromValue(dynamic value) {
    if (value == null) return null;
    if (value is Rect) return value;

    double? left;
    double? top;
    double? right;
    double? bottom;

    try {
      left = _toDouble(value.left);
      top = _toDouble(value.top);
      right = _toDouble(value.right);
      bottom = _toDouble(value.bottom);
    } catch (_) {
      left = null;
      top = null;
      right = null;
      bottom = null;
    }

    if ([left, top, right, bottom].every((element) => element != null)) {
      return Rect.fromLTRB(left!, top!, right!, bottom!);
    }

    double? width;
    double? height;

    try {
      left ??= _toDouble(value.x);
      top ??= _toDouble(value.y);
      width = _toDouble(value.width);
      height = _toDouble(value.height);
    } catch (_) {
      width = null;
      height = null;
    }

    if (width != null && height != null && left != null && top != null) {
      return Rect.fromLTWH(left, top, width, height);
    }

    if (value is Map) {
      left ??= _toDouble(value['left'] ?? value['x']);
      top ??= _toDouble(value['top'] ?? value['y']);
      right ??= _toDouble(value['right']);
      bottom ??= _toDouble(value['bottom']);
      width ??= _toDouble(value['width'] ?? value['w']);
      height ??= _toDouble(value['height'] ?? value['h']);

      if ([left, top, right, bottom].every((element) => element != null)) {
        return Rect.fromLTRB(left!, top!, right!, bottom!);
      }
      if (width != null && height != null && left != null && top != null) {
        return Rect.fromLTWH(left, top, width, height);
      }
    }

    if (value is List && value.length >= 4) {
      left ??= _toDouble(value[0]);
      top ??= _toDouble(value[1]);
      width ??= _toDouble(value[2]);
      height ??= _toDouble(value[3]);
      if (width != null && height != null && left != null && top != null) {
        return Rect.fromLTWH(left, top, width, height);
      }
    }

    return null;
  }

  Size? _extractSourceSize(YOLOResult result) {
    final dynamic dynamicResult = result;
    Size? size;
    size ??= _sizeFromDynamic(() => dynamicResult.originalImageSize);
    size ??= _sizeFromDynamic(() => dynamicResult.imageSize);
    size ??= _sizeFromDynamic(() => dynamicResult.sourceSize);
    size ??= _sizeFromDynamic(() => dynamicResult.size);
    size ??= _sizeFromDynamic(() => dynamicResult.inputSize);
    size ??= _sizeFromDynamic(() => dynamicResult.frameSize);
    if (size != null && size.width > 0 && size.height > 0) {
      return size;
    }

    final width = _doubleFromDynamic(() => dynamicResult.imageWidth) ??
        _doubleFromDynamic(() => dynamicResult.width);
    final height = _doubleFromDynamic(() => dynamicResult.imageHeight) ??
        _doubleFromDynamic(() => dynamicResult.height);
    if (width != null && height != null && width > 0 && height > 0) {
      return Size(width, height);
    }

    final rect = _rectFromDynamic(() => dynamicResult.boundingBox);
    if (rect != null && rect.right > 0 && rect.bottom > 0) {
      return Size(rect.right, rect.bottom);
    }

    return null;
  }

  Size? _sizeFromDynamic(dynamic Function() getter) {
    try {
      return _sizeFromValue(getter());
    } catch (_) {
      return null;
    }
  }

  Size? _sizeFromValue(dynamic value) {
    if (value == null) return null;
    if (value is Size) return value;
    if (value is Rect) return value.size;

    double? width;
    double? height;

    try {
      width = _toDouble(value.width);
      height = _toDouble(value.height);
    } catch (_) {
      width = null;
      height = null;
    }

    if (width != null && height != null) {
      return Size(width, height);
    }

    if (value is Map) {
      width ??= _toDouble(value['width'] ?? value['w']);
      height ??= _toDouble(value['height'] ?? value['h']);
      if (width != null && height != null) {
        return Size(width, height);
      }
    }

    if (value is List && value.length >= 2) {
      width ??= _toDouble(value[0]);
      height ??= _toDouble(value[1]);
      if (width != null && height != null) {
        return Size(width, height);
      }
    }

    return null;
  }

  Rect _denormalizeRect(Rect rect, Size size) {
    final width = size.width <= 0 ? 1.0 : size.width;
    final height = size.height <= 0 ? 1.0 : size.height;

    final isNormalized =
        rect.left >= 0 && rect.top >= 0 && rect.right <= 1.2 && rect.bottom <= 1.2;

    if (isNormalized) {
      return Rect.fromLTRB(
        rect.left * width,
        rect.top * height,
        rect.right * width,
        rect.bottom * height,
      );
    }
    return rect;
  }

  Rect _clampRectToSource(Rect rect, Size size) {
    final left = rect.left.clamp(0.0, size.width).toDouble();
    final top = rect.top.clamp(0.0, size.height).toDouble();
    final right = rect.right.clamp(0.0, size.width).toDouble();
    final bottom = rect.bottom.clamp(0.0, size.height).toDouble();
    return Rect.fromLTRB(
      left,
      top,
      math.max(left, right),
      math.max(top, bottom),
    );
  }

  double _extractConfidence(YOLOResult result) {
    final dynamic dynamicResult = result;
    final confidence = _doubleFromDynamic(() => dynamicResult.confidence) ??
        _doubleFromDynamic(() => dynamicResult.score) ??
        _doubleFromDynamic(() => dynamicResult.probability) ??
        _doubleFromDynamic(() => dynamicResult.conf) ??
        0.0;
    return confidence.clamp(0.0, 1.0);
  }

  String _extractLabel(YOLOResult result) {
    final dynamic dynamicResult = result;
    final label = _stringFromDynamic(() => dynamicResult.className) ??
        _stringFromDynamic(() => dynamicResult.label) ??
        _stringFromDynamic(() => dynamicResult.name) ??
        _stringFromDynamic(() => dynamicResult.category) ??
        _stringFromDynamic(() => dynamicResult.tag);
    if (label == null || label.trim().isEmpty) {
      return 'object';
    }
    return label.trim();
  }

  double? _doubleFromDynamic(dynamic Function() getter) {
    try {
      return _toDouble(getter());
    } catch (_) {
      return null;
    }
  }

  String? _stringFromDynamic(dynamic Function() getter) {
    try {
      final value = getter();
      if (value == null) return null;
      if (value is String) return value;
      return value.toString();
    } catch (_) {
      return null;
    }
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  bool _listEqualsDetections(
    List<DetectionViewModel> a,
    List<DetectionViewModel> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Handle performance metrics
  void onPerformanceMetrics(double fps) {
    if (_isDisposed) return;

    if ((_currentFps - fps).abs() > 0.1) {
      _currentFps = fps;
      notifyListeners();
    }
  }

  void onZoomChanged(double zoomLevel) {
    if (_isDisposed) return;

    if ((_currentZoomLevel - zoomLevel).abs() > 0.01) {
      _currentZoomLevel = zoomLevel;
      notifyListeners();
    }
  }

  void toggleSlider(SliderType type) {
    if (_isDisposed) return;

    if (_activeSlider != type) {
      _activeSlider = _activeSlider == type ? SliderType.none : type;
      notifyListeners();
    }
  }

  void updateSliderValue(double value) {
    if (_isDisposed) return;

    bool changed = false;
    switch (_activeSlider) {
      case SliderType.numItems:
        final newValue = value.toInt();
        if (_numItemsThreshold != newValue) {
          _numItemsThreshold = newValue;
          _yoloController.setNumItemsThreshold(_numItemsThreshold);
          changed = true;
        }
        break;
      case SliderType.confidence:
        if ((_confidenceThreshold - value).abs() > 0.01) {
          _confidenceThreshold = value;
          _yoloController.setConfidenceThreshold(value);
          changed = true;
        }
        break;
      case SliderType.iou:
        if ((_iouThreshold - value).abs() > 0.01) {
          _iouThreshold = value;
          _yoloController.setIoUThreshold(value);
          changed = true;
        }
        break;
      default:
        break;
    }

    if (changed) {
      notifyListeners();
    }
  }

  void setZoomLevel(double zoomLevel) {
    if (_isDisposed) return;

    if ((_currentZoomLevel - zoomLevel).abs() > 0.01) {
      _currentZoomLevel = zoomLevel;
      _yoloController.setZoomLevel(zoomLevel);
      notifyListeners();
    }
  }

  void flipCamera() {
    if (_isDisposed) return;

    _isFrontCamera = !_isFrontCamera;
    if (_isFrontCamera) _currentZoomLevel = 1.0;
    _yoloController.switchCamera();
    notifyListeners();
  }

  void toggleVoice() {
    if (_isDisposed) return;

    _isVoiceEnabled = !_isVoiceEnabled;
    if (!_isVoiceEnabled) {
      unawaited(_voiceAnnouncer.stop());
    }
    notifyListeners();
  }

  void changeModel(ModelType model) {
    if (_isDisposed) return;

    if (!_isModelLoading && model != _selectedModel) {
      _selectedModel = model;
      _loadModelForPlatform();
    }
  }

  Future<void> _loadModelForPlatform() async {
    if (_isDisposed) return;

    if (_loadingFuture != null) {
      await _loadingFuture;
      return;
    }

    _loadingFuture = _performModelLoading();
    try {
      await _loadingFuture;
    } finally {
      _loadingFuture = null;
    }
  }

  Future<void> _performModelLoading() async {
    if (_isDisposed) return;

    _isModelLoading = true;
    _loadingMessage = 'Loading ${_selectedModel.modelName} model...';
    _downloadProgress = 0.0;
    _detectionCount = 0;
    _currentFps = 0.0;
    notifyListeners();

    try {
      final modelPath = await _modelManager.getModelPath(_selectedModel);

      if (_isDisposed) return;

      _modelPath = modelPath;
      _isModelLoading = false;
      _loadingMessage = '';
      _downloadProgress = 0.0;
      notifyListeners();

      if (modelPath == null) {
        throw Exception('Failed to load ${_selectedModel.modelName} model');
      }
    } catch (e) {
      if (_isDisposed) return;

      final error = YOLOErrorHandler.handleError(
        e,
        'Failed to load model ${_selectedModel.modelName} for task ${_selectedModel.task.name}',
      );

      _isModelLoading = false;
      _loadingMessage = 'Failed to load model: ${error.message}';
      _downloadProgress = 0.0;
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _voiceAnnouncer.dispose();
    super.dispose();
  }
}
