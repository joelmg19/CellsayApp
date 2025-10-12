// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultralytics_yolo/models/yolo_result.dart';

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
    List<YOLOResult> results, {
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
    if (now.difference(_lastAnnouncement) < const Duration(seconds: 3)) {
      return;
    }

    final message = _buildMessage(results);
    if (message == null || message == _lastMessage) {
      return;
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

  String? _buildMessage(List<YOLOResult> results) {
    if (results.isEmpty) {
      if (_lastMessage == null) {
        return 'No detecto objetos frente a la cámara.';
      }
      _lastMessage = null;
      return null;
    }

    final descriptions = <String>[];
    String? warning;

    for (final result in results.take(3)) {
      final label = result.className.isNotEmpty ? result.className : 'objeto';
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
    return warning != null ? '$base $warning' : base;
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
}

class _DistanceDescription {
  const _DistanceDescription(this.description, this.isClose);

  final String description;
  final bool isClose;
}
