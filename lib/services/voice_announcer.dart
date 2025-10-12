// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:async';
import 'dart:ui';

import 'package:flutter_tts/flutter_tts.dart';
import '../models/detection_view_model.dart';

class VoiceAnnouncer {
  VoiceAnnouncer() {
    _initialization = _configure();
  }

  final FlutterTts _tts = FlutterTts();
  Future<void>? _initialization;
  DateTime _lastAnnouncement = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastMessage;

  Future<void> _configure() async {
    try {
      await _tts.setLanguage('es-ES');
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
    } catch (_) {
      // Ignore configuration errors to avoid crashing voice flow.
    }
  }

  Future<void> processDetections(
    List<DetectionViewModel> detections, {
    required bool isVoiceEnabled,
  }) async {
    if (!isVoiceEnabled) {
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
    final messageInfo = _buildMessage(detections);
    if (messageInfo == null) {
      return;
    }

    final cooldown = messageInfo.isEmergency
        ? Duration.zero
        : const Duration(seconds: 5);

    if (cooldown > Duration.zero &&
        now.difference(_lastAnnouncement) < cooldown) {
      return;
    }

    final message = messageInfo.text;
    final alreadySaid = message == _lastMessage;
    final timeSinceLast = now.difference(_lastAnnouncement);

    if (alreadySaid) {
      final emergencyRepeatWindow = const Duration(seconds: 1);
      final canRepeatEmergency =
          messageInfo.isEmergency && timeSinceLast >= emergencyRepeatWindow;
      if (!canRepeatEmergency) {
        return;
      }
    }

    try {
      await _safeStop();
      await _tts.speak(message);
      _lastAnnouncement = now;
      _lastMessage = message;
    } catch (_) {
      // Ignore speak failures to keep detection loop running.
    }
  }

  Future<void> stop() => _safeStop();

  Future<void> _safeStop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Ignore stop failures.
    }
  }

  _MessageInfo? _buildMessage(List<DetectionViewModel> detections) {
    if (detections.isEmpty) {
      if (_lastMessage == null) {
        return const _MessageInfo(
          text: 'No detecto objetos frente a la cámara.',
          isEmergency: false,
        );
      }
      _lastMessage = null;
      return null;
    }

    final descriptions = <String>[];
    String? warning;
    var hasEmergency = false;

    for (final detection in detections.take(3)) {
      final label = detection.label.isNotEmpty ? detection.label : 'objeto';
      final distance = _describeDistance(detection);
      final side = _describeSide(detection);

      final directionText = side != null ? ' hacia $side' : '';
      descriptions.add(
        '$label ${distance.description}$directionText',
      );

      if (distance.isClose) {
        hasEmergency = hasEmergency || distance.isEmergency;
      }

      if (warning == null && distance.isEmergency) {
        final warningSide = side != null ? 'a $side' : 'al frente';
        warning = 'Cuidado $warningSide, $label está muy cerca.';
      }
    }

    if (descriptions.isEmpty) {
      return null;
    }

    final base = 'Veo ${descriptions.join(', ')}.';
    final text = warning != null ? '$base $warning' : base;
    return _MessageInfo(text: text, isEmergency: hasEmergency || warning != null);
  }

  _DistanceDescription _describeDistance(DetectionViewModel detection) {
    final size = detection.sourceSize;
    if (size.width <= 0 || size.height <= 0) {
      return const _DistanceDescription(
        'a una distancia desconocida',
        isClose: false,
        isEmergency: false,
      );
    }

    final widthRatio =
        (detection.boundingBox.width / size.width).clamp(0.0, 1.0);
    final heightRatio =
        (detection.boundingBox.height / size.height).clamp(0.0, 1.0);
    final areaRatio = (widthRatio * heightRatio).clamp(0.0, 1.0);

    if (areaRatio >= 0.28) {
      return const _DistanceDescription(
        'a menos de medio metro',
        isClose: true,
        isEmergency: true,
      );
    } else if (areaRatio >= 0.16) {
      return const _DistanceDescription(
        'a aproximadamente un metro',
        isClose: true,
        isEmergency: false,
      );
    } else if (areaRatio >= 0.08) {
      return const _DistanceDescription(
        'a unos dos metros',
        isClose: false,
        isEmergency: false,
      );
    } else {
      return const _DistanceDescription(
        'a más de tres metros',
        isClose: false,
        isEmergency: false,
      );
    }
  }

  String? _describeSide(DetectionViewModel detection) {
    final size = detection.sourceSize;
    if (size.width <= 0) return null;

    final centerX = detection.boundingBox.center.dx / size.width;

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
}

class _DistanceDescription {
  const _DistanceDescription(
    this.description, {
    required this.isClose,
    required this.isEmergency,
  });

  final String description;
  final bool isClose;
  final bool isEmergency;
}

class _MessageInfo {
  const _MessageInfo({required this.text, required this.isEmergency});

  final String text;
  final bool isEmergency;
}
