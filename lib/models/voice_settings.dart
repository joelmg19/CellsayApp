/// Configuration for the voice announcer.
class VoiceSettings {
  const VoiceSettings({
    this.language = 'es-ES',
    this.speechRate = 0.45,
    this.pitch = 1.0,
    this.volume = 1.0,
  });

  final String language;
  final double speechRate;
  final double pitch;
  final double volume;

  VoiceSettings copyWith({
    String? language,
    double? speechRate,
    double? pitch,
    double? volume,
  }) {
    return VoiceSettings(
      language: language ?? this.language,
      speechRate: speechRate ?? this.speechRate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
    );
  }
}
