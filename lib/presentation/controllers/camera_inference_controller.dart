// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ultralytics_yolo/models/yolo_result.dart';
import 'package:ultralytics_yolo/utils/error_handler.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import '../../models/detection_insight.dart';
import '../../models/models.dart';
import '../../models/voice_settings.dart';
import '../../services/detection_post_processor.dart';
import '../../services/model_manager.dart';
import '../../services/voice_announcer.dart';
import '../../services/weather_service.dart';

/// Controller that manages the state and business logic for camera inference
class CameraInferenceController extends ChangeNotifier {
  // Detection state
  int _detectionCount = 0;
  double _currentFps = 0.0;
  int _frameCount = 0;
  DateTime _lastFpsUpdate = DateTime.now();
  DateTime _lastResultTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastNonEmptyResult;
  ProcessedDetections _processedDetections = ProcessedDetections.empty;
  SafetyAlerts _safetyAlerts = const SafetyAlerts();

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
  double _fontScale = 1.0;
  VoiceSettings _voiceSettings = const VoiceSettings();
  String? _voiceCommandStatus;
  bool _areControlsLocked = false;

  // Controllers
  final _yoloController = YOLOViewController();
  late final ModelManager _modelManager;
  final DetectionPostProcessor _postProcessor = DetectionPostProcessor();
  final VoiceAnnouncer _voiceAnnouncer = VoiceAnnouncer();
  final WeatherService _weatherService = WeatherService();

  // Performance optimization
  bool _isDisposed = false;
  Future<void>? _loadingFuture;
  Timer? _statusTimer;
  DateTime _currentTime = DateTime.now();
  WeatherInfo? _weatherInfo;
  DateTime _lastWeatherFetch = DateTime.fromMillisecondsSinceEpoch(0);
  String? _connectionAlert;
  String? _cameraAlert;

  // Getters
  int get detectionCount => _detectionCount;
  double get currentFps => _currentFps;
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
  double get fontScale => _fontScale;
  VoiceSettings get voiceSettings => _voiceSettings;
  bool get areControlsLocked => _areControlsLocked;
  ProcessedDetections get processedDetections => _processedDetections;
  SafetyAlerts get safetyAlerts => _safetyAlerts;
  String get formattedTime => DateFormat.Hm().format(_currentTime);
  String? get weatherSummary => _weatherInfo?.formatSummary();
  List<String> get closeObstacles => _processedDetections.closeObstacleLabels;
  List<String> get movementWarnings => _processedDetections.movementWarnings;
  TrafficLightSignal get trafficLightSignal =>
      _processedDetections.trafficLightSignal;
  String? get connectionAlert => _connectionAlert;
  String? get cameraAlert => _cameraAlert;
  String? get voiceCommandStatus => _voiceCommandStatus;
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
    _statusTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _onStatusTick());
    unawaited(_refreshWeather());
  }

  /// Initialize the controller
  Future<void> initialize() async {
    await _loadModelForPlatform();
    _yoloController.setThresholds(
      confidenceThreshold: _confidenceThreshold,
      iouThreshold: _iouThreshold,
      numItemsThreshold: _numItemsThreshold,
    );
    _postProcessor.updateThresholds(iouThreshold: _iouThreshold);
  }

  /// Handle detection results and calculate FPS
  void onDetectionResults(List<YOLOResult> results) {
    if (_isDisposed) return;

    _frameCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastFpsUpdate).inMilliseconds;
    _lastResultTimestamp = now;

    if (elapsed >= 1000) {
      _currentFps = _frameCount * 1000 / elapsed;
      _frameCount = 0;
      _lastFpsUpdate = now;
    }

    final previousObstacles =
        _processedDetections.closeObstacleLabels.join('|');
    final previousMovements =
        _processedDetections.movementWarnings.join('|');
    final previousSignal = _processedDetections.trafficLightSignal;

    final processed = _postProcessor.process(results);
    final filtered = processed.filteredResults;
    final filteredCount = filtered.length;

    bool shouldNotify = false;

    if (_detectionCount != filteredCount) {
      _detectionCount = filteredCount;
      shouldNotify = true;
    }

    if (filteredCount > 0) {
      _lastNonEmptyResult = now;
      if (_cameraAlert != null) {
        _cameraAlert = null;
        shouldNotify = true;
      }
    }

    final newObstacles = processed.closeObstacleLabels.join('|');
    final newMovements = processed.movementWarnings.join('|');

    if (previousObstacles != newObstacles ||
        previousMovements != newMovements ||
        previousSignal != processed.trafficLightSignal) {
      shouldNotify = true;
    }

    if (_connectionAlert != null) {
      _connectionAlert = null;
      shouldNotify = true;
    }

    _processedDetections = processed;
    _safetyAlerts = SafetyAlerts(
      connectionAlert: _connectionAlert,
      cameraAlert: _cameraAlert,
    );

    if (shouldNotify) {
      notifyListeners();
    }

    unawaited(
      _voiceAnnouncer.processDetections(
        filtered,
        isVoiceEnabled: _isVoiceEnabled,
        insights: processed,
        alerts: _safetyAlerts,
      ),
    );
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
    if (_isDisposed || _areControlsLocked) return;

    if ((_currentZoomLevel - zoomLevel).abs() > 0.01) {
      _currentZoomLevel = zoomLevel;
      notifyListeners();
    }
  }

  void toggleSlider(SliderType type) {
    if (_isDisposed || _areControlsLocked) return;

    final newValue = _activeSlider == type ? SliderType.none : type;
    if (newValue != _activeSlider) {
      _activeSlider = newValue;
      notifyListeners();
    }
  }

  void updateSliderValue(double value) {
    if (_isDisposed || _areControlsLocked) return;

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
          _postProcessor.updateThresholds(iouThreshold: value);
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
    if (_isDisposed || _areControlsLocked) return;

    if ((_currentZoomLevel - zoomLevel).abs() > 0.01) {
      _currentZoomLevel = zoomLevel;
      _yoloController.setZoomLevel(zoomLevel);
      notifyListeners();
    }
  }

  void flipCamera() {
    if (_isDisposed || _areControlsLocked) return;

    _isFrontCamera = !_isFrontCamera;
    if (_isFrontCamera) _currentZoomLevel = 1.0;
    _yoloController.switchCamera();
    notifyListeners();
  }

  void toggleVoice() {
    if (_isDisposed || _areControlsLocked) return;

    _isVoiceEnabled = !_isVoiceEnabled;
    if (!_isVoiceEnabled) {
      unawaited(_voiceAnnouncer.stop());
    }
    _voiceCommandStatus =
        _isVoiceEnabled ? 'Narración activada.' : 'Narración desactivada.';
    if (_isVoiceEnabled) {
      unawaited(_announceSystemMessage(_voiceCommandStatus!));
    }
    notifyListeners();
  }

  void increaseFontScale() {
    if (_isDisposed || _areControlsLocked) return;

    final newScale = (_fontScale + 0.1).clamp(0.8, 2.0);
    if ((newScale - _fontScale).abs() > 0.01) {
      _fontScale = newScale;
      _voiceCommandStatus = 'Tamaño de texto aumentado.';
      notifyListeners();
    }
  }

  void decreaseFontScale() {
    if (_isDisposed || _areControlsLocked) return;

    final newScale = (_fontScale - 0.1).clamp(0.8, 2.0);
    if ((newScale - _fontScale).abs() > 0.01) {
      _fontScale = newScale;
      _voiceCommandStatus = 'Tamaño de texto reducido.';
      notifyListeners();
    }
  }

  Future<void> repeatLastInstruction() => _voiceAnnouncer.repeatLastMessage();

  void toggleControlsLock() {
    if (_isDisposed) return;

    _areControlsLocked = !_areControlsLocked;
    if (_areControlsLocked && _activeSlider != SliderType.none) {
      _activeSlider = SliderType.none;
    }
    notifyListeners();
  }

  void updateVoiceSettings(VoiceSettings settings) {
    if (_isDisposed) return;

    _voiceSettings = settings;
    unawaited(_voiceAnnouncer.updateSettings(settings));
    _voiceCommandStatus = 'Configuración de voz actualizada.';
    notifyListeners();
  }

  Future<void> refreshWeather() async {
    await _refreshWeather(force: true);
  }

  void handleVoiceCommand(String command) {
    if (_isDisposed) return;

    final normalized = command.toLowerCase().trim();
    if (normalized.isEmpty) {
      return;
    }

    String? feedback;
    bool recognized = false;

    if (normalized.contains('repet')) {
      recognized = true;
      feedback = 'Repitiendo la última instrucción.';
      unawaited(repeatLastInstruction());
    } else if ((normalized.contains('sube') || normalized.contains('aumenta')) &&
        (normalized.contains('letra') || normalized.contains('fuente') ||
            normalized.contains('texto'))) {
      recognized = true;
      increaseFontScale();
      feedback = 'Aumentando tamaño de texto.';
    } else if ((normalized.contains('baja') || normalized.contains('disminuye')) &&
        (normalized.contains('letra') || normalized.contains('fuente') ||
            normalized.contains('texto'))) {
      recognized = true;
      decreaseFontScale();
      feedback = 'Reduciendo tamaño de texto.';
    } else if ((normalized.contains('activa') ||
            normalized.contains('enciende') ||
            normalized.contains('activar')) &&
        (normalized.contains('voz') || normalized.contains('narr'))) {
      recognized = true;
      if (!_isVoiceEnabled) {
        toggleVoice();
      }
      feedback = _isVoiceEnabled ? null : 'Narración activada.';
    } else if ((normalized.contains('desactiva') ||
            normalized.contains('apaga') ||
            normalized.contains('silencio')) &&
        (normalized.contains('voz') || normalized.contains('narr'))) {
      recognized = true;
      if (_isVoiceEnabled) {
        toggleVoice();
      }
      feedback = !_isVoiceEnabled ? null : 'Narración desactivada.';
    } else if (normalized.contains('clima') || normalized.contains('tiempo')) {
      recognized = true;
      unawaited(refreshWeather());
      feedback = null;
    }

    if (!recognized) {
      _voiceCommandStatus = 'Comando no reconocido.';
      unawaited(_announceSystemMessage('No entendí el comando.'));
    } else {
      _voiceCommandStatus = feedback;
      if (feedback != null) {
        unawaited(_announceSystemMessage(feedback));
      }
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
    _postProcessor.clearHistory();
    _processedDetections = ProcessedDetections.empty;
    _safetyAlerts = const SafetyAlerts();
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

  void _onStatusTick() {
    if (_isDisposed) return;

    final now = DateTime.now();
    bool shouldNotify = false;

    if (now.difference(_currentTime).inSeconds >= 1) {
      _currentTime = now;
      shouldNotify = true;
    }

    final hasModel = _modelPath != null && !_isModelLoading;
    final connectionDelay = now.difference(_lastResultTimestamp);
    String? newConnectionAlert;
    if (hasModel && connectionDelay > const Duration(seconds: 5)) {
      newConnectionAlert =
          'No recibo datos de detección, revisa tu conexión o reinicia la cámara.';
    }

    if (newConnectionAlert != _connectionAlert) {
      _connectionAlert = newConnectionAlert;
      shouldNotify = true;
    }

    String? newCameraAlert = _cameraAlert;
    final lastNonEmpty = _lastNonEmptyResult;
    if (lastNonEmpty != null) {
      if (now.difference(lastNonEmpty) > const Duration(seconds: 6)) {
        newCameraAlert =
            'No detecto objetos desde hace varios segundos, verifica que la cámara no esté obstruida.';
      }
    } else if (hasModel && connectionDelay > const Duration(seconds: 8)) {
      newCameraAlert = 'No puedo ver la imagen de la cámara.';
    } else if (hasModel && connectionDelay < const Duration(seconds: 3)) {
      newCameraAlert = null;
    }

    if (newCameraAlert != _cameraAlert) {
      _cameraAlert = newCameraAlert;
      shouldNotify = true;
    }

    _safetyAlerts = SafetyAlerts(
      connectionAlert: _connectionAlert,
      cameraAlert: _cameraAlert,
    );

    if (now.difference(_lastWeatherFetch) > const Duration(minutes: 30)) {
      unawaited(_refreshWeather());
    }

    if (shouldNotify) {
      notifyListeners();
    }
  }

  Future<void> _refreshWeather({bool force = false}) async {
    if (_isDisposed) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastWeatherFetch) < const Duration(minutes: 15)) {
      return;
    }

    final info = await _weatherService.loadCurrentWeather();
    if (_isDisposed) return;

    _lastWeatherFetch = now;
    if (info != null) {
      _weatherInfo = info;
      _voiceCommandStatus = 'Clima actualizado.';
      notifyListeners();
      if (force) {
        final summary = info.formatSummary();
        unawaited(
          _announceSystemMessage('El clima actual es $summary'),
        );
      }
    } else if (force) {
      _voiceCommandStatus = 'No fue posible obtener el clima.';
      notifyListeners();
      unawaited(
        _announceSystemMessage('No fue posible obtener el clima actual.'),
      );
    }
  }

  Future<void> _announceSystemMessage(String message, {bool force = false}) async {
    if (!force && !_isVoiceEnabled) return;

    await _voiceAnnouncer.processDetections(
      const <YOLOResult>[],
      isVoiceEnabled: true,
      insights: ProcessedDetections.empty,
      alerts: SafetyAlerts(connectionAlert: message),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _voiceAnnouncer.dispose();
    _statusTimer?.cancel();
    _weatherService.dispose();
    super.dispose();
  }
}
