import 'package:flutter_tts/flutter_tts.dart';

/// Utility helpers to keep text-to-speech messages consistent and safe when
/// reporting distance estimations.
class TtsHelper {
  TtsHelper(this.tts);

  final FlutterTts tts;

  /// Speaks a distance estimation message using the provided [FlutterTts]
  /// instance. Falls back to a safe error message when the distance is not
  /// available or invalid.
  void speakDistance(double? meters, String label) {
    final text = hasValidDistance(meters)
        ? 'Veo un $label a aproximadamente ${meters!.toStringAsFixed(1)} metros'
        : 'No puedo estimar la distancia del $label';
    tts.speak(text);
  }

  /// Returns `true` if the distance is finite and positive.
  bool hasValidDistance(double? meters) {
    return meters != null && !meters.isNaN && !meters.isInfinite && meters > 0;
  }

  /// Provides a short clause describing the distance for composing larger
  /// sentences. Example: `a aproximadamente 1.2 metros`.
  String distanceClause(double? meters) {
    if (!hasValidDistance(meters)) {
      return 'a una distancia desconocida';
    }
    return 'a aproximadamente ${meters!.toStringAsFixed(1)} metros';
  }
}
