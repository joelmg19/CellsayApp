// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:async';

import 'package:flutter/services.dart';

typedef VoiceCommandResultCallback = void Function(String text);
typedef VoiceCommandErrorCallback = void Function(String message);
typedef VoiceCommandListeningCallback = void Function(bool isListening);

/// Provides access to the native voice recognition service used for commands.
class VoiceCommandService {
  VoiceCommandService();

  static const MethodChannel _methodChannel =
      MethodChannel('voice_commands/methods');
  static const EventChannel _eventChannel =
      EventChannel('voice_commands/events');

  Stream<dynamic>? _eventStream;
  StreamSubscription<dynamic>? _eventSubscription;

  bool _isAvailable = false;
  bool _isListening = false;
  bool _initializing = false;
  String? _cachedLocale;

  Future<bool> _ensureInitialized({
    VoiceCommandErrorCallback? onError,
  }) async {
    if (_isAvailable) {
      return true;
    }

    if (_initializing) {
      while (_initializing) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return _isAvailable;
    }

    _initializing = true;
    try {
      final response =
          await _methodChannel.invokeMapMethod<String, dynamic>('initialize');
      if (response == null) {
        onError?.call(
          'No se pudo preparar el reconocimiento de voz. Intenta nuevamente.',
        );
        _isAvailable = false;
        return false;
      }

      final available = response['available'] == true;
      _isAvailable = available;

      final errorMessage = response['error'] as String?;
      if (!available) {
        if (errorMessage != null && errorMessage.isNotEmpty) {
          onError?.call(errorMessage);
        } else {
          onError?.call(
            'El reconocimiento de voz no está disponible en este dispositivo.',
          );
        }
        return false;
      }

      if (_cachedLocale == null) {
        final systemLocale = response['systemLocale'] as String?;
        final locales = (response['locales'] as List<dynamic>? ?? const [])
            .cast<String>();

        _cachedLocale = systemLocale ?? _findSpanishLocale(locales);
        _cachedLocale ??= locales.isNotEmpty ? locales.first : null;
      }
    } on PlatformException catch (error) {
      onError?.call(
        error.message ??
            'No fue posible inicializar el reconocimiento de voz.',
      );
      _isAvailable = false;
      return false;
    } finally {
      _initializing = false;
    }

    return _isAvailable;
  }

  String? _findSpanishLocale(List<String> locales) {
    for (final locale in locales) {
      if (locale.toLowerCase().startsWith('es')) {
        return locale;
      }
    }
    return null;
  }

  Future<bool> startListening({
    required VoiceCommandResultCallback onResult,
    required VoiceCommandErrorCallback onError,
    VoiceCommandListeningCallback? onStatus,
    Duration listenFor = const Duration(seconds: 8),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    final available = await _ensureInitialized(onError: onError);
    if (!available) {
      onError('El reconocimiento de voz no está disponible.');
      return false;
    }

    await _eventSubscription?.cancel();
    _eventStream ??= _eventChannel.receiveBroadcastStream();
    _eventSubscription = _eventStream!.listen(
      (dynamic event) {
        if (event is! Map) {
          return;
        }
        final type = event['type'];
        switch (type) {
          case 'status':
            final listening = event['listening'] == true;
            _isListening = listening;
            onStatus?.call(listening);
            break;
          case 'result':
            final text = (event['text'] as String? ?? '').trim();
            if (text.isEmpty) {
              onError('No se escuchó ningún comando.');
            } else {
              onResult(text);
            }
            break;
          case 'error':
            final message =
                (event['message'] as String?) ?? 'Error desconocido.';
            _isListening = false;
            onError(message);
            break;
          case 'timeout':
            _isListening = false;
            onError('Tiempo de escucha agotado.');
            break;
        }
      },
      onError: (error) {
        onError('Error en el reconocimiento de voz: $error');
      },
      onDone: () {
        _eventSubscription = null;
      },
    );

    final localeId = _cachedLocale ?? 'es_ES';

    try {
      final started = await _methodChannel.invokeMethod<bool>('start', {
        'locale': localeId,
        'listenFor': listenFor.inMilliseconds,
        'pauseFor': pauseFor.inMilliseconds,
      });

      final isStarted = started ?? false;
      if (!isStarted) {
        onError('No se pudo iniciar la escucha.');
        _isListening = false;
      } else {
        onStatus?.call(true);
        _isListening = true;
      }
      if (!isStarted) {
        await _eventSubscription?.cancel();
        _eventSubscription = null;
      }
      return isStarted;
    } on PlatformException catch (error) {
      onError('Error al iniciar la escucha: ${error.message ?? error}');
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      _isListening = false;
      return false;
    }
  }

  Future<void> stopListening() async {
    _isListening = false;
    await _methodChannel.invokeMethod('stop');
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  Future<void> cancelListening() async {
    _isListening = false;
    await _methodChannel.invokeMethod('cancel');
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  bool get isListening => _isListening;

  Future<void> dispose() async {
    await cancelListening();
  }
}
