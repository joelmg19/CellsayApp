// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultralytics_yolo/models/yolo_result.dart';
import '../models/detection_insight.dart';
import '../models/voice_settings.dart';

const Map<String, String> _labelTranslations = {
  'person': 'persona',
  'bicycle': 'bicicleta',
  'car': 'auto',
  'motorcycle': 'motocicleta',
  'motorbike': 'motocicleta',
  'airplane': 'avión',
  'aeroplane': 'avión',
  'bus': 'autobús',
  'train': 'tren',
  'truck': 'camión',
  'boat': 'barco',
  'traffic light': 'semáforo',
  'trafficlight': 'semáforo',
  'fire hydrant': 'hidrante',
  'firehydrant': 'hidrante',
  'stop sign': 'señal de alto',
  'parking meter': 'parquímetro',
  'parkingmeter': 'parquímetro',
  'bench': 'banco',
  'bird': 'pájaro',
  'cat': 'gato',
  'dog': 'perro',
  'horse': 'caballo',
  'sheep': 'oveja',
  'cow': 'vaca',
  'elephant': 'elefante',
  'bear': 'oso',
  'zebra': 'cebra',
  'giraffe': 'jirafa',
  'backpack': 'mochila',
  'umbrella': 'paraguas',
  'handbag': 'bolso',
  'tie': 'corbata',
  'suitcase': 'valija',
  'frisbee': 'frisbee',
  'skis': 'esquís',
  'snowboard': 'tabla de snowboard',
  'sports ball': 'pelota deportiva',
  'kite': 'cometa',
  'baseball bat': 'bate de béisbol',
  'baseball glove': 'guante de béisbol',
  'skateboard': 'patineta',
  'surfboard': 'tabla de surf',
  'tennis racket': 'raqueta de tenis',
  'tennisracket': 'raqueta de tenis',
  'bottle': 'botella',
  'wine glass': 'copa de vino',
  'wineglass': 'copa de vino',
  'cup': 'taza',
  'fork': 'tenedor',
  'knife': 'cuchillo',
  'spoon': 'cuchara',
  'bowl': 'bol',
  'banana': 'banana',
  'apple': 'manzana',
  'sandwich': 'sándwich',
  'orange': 'naranja',
  'broccoli': 'brócoli',
  'carrot': 'zanahoria',
  'hot dog': 'pancho',
  'pizza': 'pizza',
  'donut': 'donut',
  'cake': 'torta',
  'chair': 'silla',
  'couch': 'sofá',
  'potted plant': 'planta en maceta',
  'pottedplant': 'planta en maceta',
  'bed': 'cama',
  'dining table': 'mesa de comedor',
  'diningtable': 'mesa de comedor',
  'toilet': 'inodoro',
  'tv': 'televisor',
  'tv monitor': 'televisor',
  'tvmonitor': 'televisor',
  'laptop': 'computadora portátil',
  'mouse': 'ratón',
  'remote': 'control remoto',
  'keyboard': 'teclado',
  'cell phone': 'teléfono celular',
  'cellphone': 'teléfono celular',
  'mobile phone': 'teléfono móvil',
  'microwave': 'microondas',
  'oven': 'horno',
  'toaster': 'tostadora',
  'sink': 'lavabo',
  'refrigerator': 'refrigerador',
  'book': 'libro',
  'clock': 'reloj',
  'vase': 'florero',
  'scissors': 'tijeras',
  'teddy bear': 'oso de peluche',
  'teddybear': 'oso de peluche',
  'hair drier': 'secador de pelo',
  'hairdryer': 'secador de pelo',
  'toothbrush': 'cepillo de dientes',
};

class VoiceAnnouncer {
  VoiceAnnouncer({VoiceSettings initialSettings = const VoiceSettings()})
      : _settings = initialSettings {
    _initialization = _configure();
  }

  final FlutterTts _tts = FlutterTts();
  Future<void>? _initialization;
  static const Duration _minimumPause = Duration(seconds: 3);
  DateTime _lastAnnouncement = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastMessage;
  VoiceSettings _settings;
  bool _isPaused = false;

  Future<void> _configure() async {
    try {
      await _tts.setLanguage(_settings.language);
      await _tts.setSpeechRate(_settings.speechRate);
      await _tts.setPitch(_settings.pitch);
      await _tts.setVolume(_settings.volume);
    } catch (_) {
      // Ignore configuration errors to avoid crashing voice flow.
    }
  }

  Future<void> processDetections(
    List<YOLOResult> results, {
    required bool isVoiceEnabled,
    ProcessedDetections insights = ProcessedDetections.empty,
    SafetyAlerts alerts = const SafetyAlerts(),
  }) async {
    if (!isVoiceEnabled || _isPaused) {
      _lastMessage = null;
      unawaited(_safeStop());
      return;
    }

    final init = _initialization;
    if (init != null) {
      await init;
      _initialization = null;
    }

    final now = DateTime.now();
    if (now.difference(_lastAnnouncement) < _minimumPause) {
      return;
    }

    final message = _buildMessage(results, insights, alerts);
    if (message == null || message == _lastMessage) {
      return;
    }

    try {
      await _safeStop();
      await _tts.speak(message);
      _lastAnnouncement = DateTime.now();
      _lastMessage = message;
    } catch (_) {
      // Ignore speak failures to keep detection loop running.
    }
  }

  Future<void> stop() => _safeStop();

  void setPaused(bool value) {
    if (_isPaused == value) return;
    _isPaused = value;
    _lastMessage = null;
    if (value) {
      unawaited(_safeStop());
    }
  }

  Future<void> updateSettings(VoiceSettings settings) async {
    _settings = settings;
    try {
      await _tts.setLanguage(settings.language);
    } catch (_) {}
    try {
      await _tts.setSpeechRate(settings.speechRate);
    } catch (_) {}
    try {
      await _tts.setPitch(settings.pitch);
    } catch (_) {}
    try {
      await _tts.setVolume(settings.volume);
    } catch (_) {}
  }

  Future<void> repeatLastMessage() async {
    final message = _lastMessage;
    if (message == null) {
      return;
    }
    try {
      await _safeStop();
      await _tts.speak(message);
      _lastAnnouncement = DateTime.now();
    } catch (_) {}
  }

  String? get lastMessage => _lastMessage;

  Future<void> _safeStop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Ignore stop failures.
    }
  }

  String? _buildMessage(
    List<YOLOResult> results,
    ProcessedDetections insights,
    SafetyAlerts alerts,
  ) {
    final alertMessages = alerts.toList();
    if (alertMessages.isNotEmpty) {
      return alertMessages.join(' ');
    }

    final filteredResults = insights.filteredResults.isNotEmpty
        ? insights.filteredResults
        : results;

    if (filteredResults.isEmpty) {
      if (_lastMessage == null) {
        return 'No detecto objetos frente a la cámara.';
      }
      _lastMessage = null;
      return null;
    }

    final descriptions = <String>[];
    String? warning;

    for (final result in filteredResults.take(3)) {
      final rawLabel = result.className.isNotEmpty ? result.className : 'objeto';
      final label = _localizeLabel(rawLabel);
      final rect = _extractRect(result);
      final distance = _describeDistance(rect);
      final side = _describeSide(rect);

      final directionText = side != null ? ' hacia $side' : '';
      descriptions.add(
        '$label ${distance.description}$directionText',
      );

      if (warning == null && distance.isClose) {
        final warningSide = side != null ? 'a $side' : 'al frente';
        warning = 'Cuidado $warningSide, $label está muy cerca.';
      }
    }

    if (descriptions.isEmpty) {
      return null;
    }

    final base = 'Veo ${descriptions.join(', ')}.';
    final movement = _describeMovementWarnings(insights) ?? '';

    final obstacle = insights.hasCloseObstacle
        ? ' Obstáculo cercano detectado: ${_localizeLabels(insights.closeObstacleLabels).join(', ')}.'
        : '';

    final traffic = _describeTrafficLight(insights.trafficLightSignal);

    return [base, warning, obstacle, movement, traffic]
        .where((element) => element != null && element.isNotEmpty)
        .join(' ')
        .trim();
  }

  Rect? _extractRect(YOLOResult result) {
    final dynamic dynamicResult = result;
    Rect? rect;
    rect ??= _rectFromDynamic(() => dynamicResult.box as Rect?);
    rect ??= _rectFromDynamic(() => dynamicResult.boundingBox as Rect?);
    rect ??= _rectFromDynamic(() => dynamicResult.rect as Rect?);
    rect ??= _rectFromDynamic(() => dynamicResult.bbox as Rect?);
    return rect;
  }

  Rect? _rectFromDynamic(dynamic Function() getter) {
    try {
      final value = getter();
      return _rectFromValue(value);
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
      left ??= null;
      top ??= null;
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
      width ??= _toDouble(value['width']);
      height ??= _toDouble(value['height']);

      if ([left, top, right, bottom].every((element) => element != null)) {
        return Rect.fromLTRB(left!, top!, right!, bottom!);
      }
      if (width != null && height != null && left != null && top != null) {
        return Rect.fromLTWH(left, top, width, height);
      }
    }

    return null;
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

  _DistanceDescription _describeDistance(Rect? rect) {
    if (rect == null) {
      return const _DistanceDescription('a una distancia desconocida', false);
    }

    final area = max(rect.width, 0) * max(rect.height, 0);
    final normalized = area.clamp(0.0, 1.0);

    if (normalized >= 0.25) {
      return const _DistanceDescription('a aproximadamente medio metro', true);
    } else if (normalized >= 0.12) {
      return const _DistanceDescription('a aproximadamente un metro', true);
    } else if (normalized >= 0.05) {
      return const _DistanceDescription('a unos dos metros', false);
    } else {
      return const _DistanceDescription('a más de tres metros', false);
    }
  }

  String? _describeSide(Rect? rect) {
    if (rect == null) return null;
    final centerX = rect.center.dx;

    if (centerX < 0.33) {
      return 'la izquierda';
    } else if (centerX > 0.66) {
      return 'la derecha';
    }
    return 'el centro';
  }

  void dispose() {
    unawaited(_safeStop());
  }

  String _localizeLabel(String label) {
    final normalized = label
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.isEmpty) {
      return 'objeto';
    }

    final translation = _labelTranslations[normalized];
    if (translation != null) {
      return translation;
    }

    if (normalized.endsWith('s')) {
      final singular = normalized.substring(0, normalized.length - 1);
      final singularTranslation = _labelTranslations[singular];
      if (singularTranslation != null) {
        return singularTranslation;
      }
    }

    return normalized;
  }

  Iterable<String> _localizeLabels(Iterable<String> labels) sync* {
    for (final label in labels) {
      yield _localizeLabel(label);
    }
  }

  String? _describeTrafficLight(TrafficLightSignal signal) {
    switch (signal) {
      case TrafficLightSignal.green:
        return 'Semáforo en verde, es seguro avanzar con precaución.';
      case TrafficLightSignal.red:
        return 'Semáforo en rojo, detente y espera.';
      case TrafficLightSignal.unknown:
        return null;
    }
  }

  String? _describeMovementWarnings(ProcessedDetections insights) {
    if (!insights.hasMovementWarnings) {
      return null;
    }

    final localized = insights.movementWarnings
        .map(_localizeMovementWarning)
        .where((warning) => warning.isNotEmpty)
        .toList();

    if (localized.isEmpty) {
      return null;
    }

    return ' Peligro en movimiento: ${localized.join(', ')}.';
  }

  String _localizeMovementWarning(String warning) {
    const suffix = ' acercándose rápidamente';
    if (warning.endsWith(suffix)) {
      final label = warning.substring(0, warning.length - suffix.length).trim();
      final localizedLabel = _localizeLabel(label);
      return '$localizedLabel$suffix';
    }
    return warning;
  }
}

class _DistanceDescription {
  const _DistanceDescription(this.description, this.isClose);

  final String description;
  final bool isClose;
}
