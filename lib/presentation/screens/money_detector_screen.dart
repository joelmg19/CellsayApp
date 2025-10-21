import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image/image.dart' as img;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:tflite_flutter/tflite_flutter.dart';

class MoneyDetectorScreen extends StatefulWidget {
  const MoneyDetectorScreen({super.key});

  @override
  State<MoneyDetectorScreen> createState() => _MoneyDetectorScreenState();
}

class _MoneyDetectorScreenState extends State<MoneyDetectorScreen> {
  CameraController? _controller;
  Interpreter? _interpreter;
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isModelLoaded = false;
  bool _isCameraReady = false;
  bool _isAnalyzing = false;
  bool _hasWelcomed = false;
  bool _isListening = false;
  bool _isLoopRunning = false;
  String _lastResult = '';

  final List<String> _labels = ['1000', '2000', '5000', '10000', '20000'];
  static const Set<String> _noiseTokens = {
    'clp',
    'peso',
    'pesos',
    'billete',
    'moneda',
    'mx\$',
    'mxn',
  };

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    await _initializeCamera();
    await _loadModel();

    await Future.delayed(const Duration(seconds: 1));

    if (!_hasWelcomed) {
      _hasWelcomed = true;
      await _speak(
        "Bienvenido a la sección de billetes chilenos. Di 'Analízalo' cuando quieras identificar el billete.",
      );
      _tts.setCompletionHandler(() {
        if (!_isLoopRunning) {
          _startListeningLoop();
        }
      });
    } else {
      _startListeningLoop();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        await _speak('No se encontró una cámara disponible.');
        return;
      }
      final camera = cameras.first;
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _isCameraReady = true;
      });
    } catch (error) {
      debugPrint('❌ Error al inicializar cámara: $error');
      await _speak('No pude iniciar la cámara.');
    }
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/dinerocl.tflite');
      setState(() => _isModelLoaded = true);
      debugPrint('✅ Modelo cargado correctamente');
    } catch (error) {
      debugPrint('❌ Error al cargar modelo: $error');
      await _speak('No pude cargar el modelo de billetes.');
    }
  }

  Future<void> _startListeningLoop() async {
    if (_isLoopRunning || !mounted) return;
    _isLoopRunning = true;
    while (mounted) {
      await _listenForCommand();
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _isLoopRunning = false;
  }

  Future<void> _listenForCommand() async {
    if (!_isModelLoaded || !_isCameraReady || _isListening) {
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        debugPrint('🎤 Estado: $status');
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
        }
      },
      onError: (error) {
        debugPrint('❌ Error STT: $error');
        _isListening = false;
      },
    );

    if (!available) {
      await _speak('No se pudo activar el micrófono.');
      return;
    }

    _isListening = true;
    debugPrint('🎧 Escuchando...');

    await _speech.listen(
      localeId: 'es_CL',
      partialResults: false,
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 7),
      cancelOnError: false,
      onResult: (result) async {
        if (!result.finalResult) return;
        final command = result.recognizedWords.toLowerCase().trim();
        debugPrint('🗣 Comando detectado: $command');

        if (_shouldAnalyze(command) && !_isAnalyzing) {
          await _speech.stop();
          await _speak('Analizando billete...');
          await Future.delayed(const Duration(seconds: 1));
          await _analyzeOnce();
        }
      },
    );
  }

  bool _shouldAnalyze(String command) {
    final normalized = _normalizeCommand(command);
    return normalized.contains('analizalo') ||
        normalized.contains('analiza lo') ||
        normalized.contains('analizar');
  }

  String _normalizeCommand(String command) {
    var normalized = command
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
    for (final token in _noiseTokens) {
      normalized = normalized.replaceAll(token, '').trim();
    }
    return normalized;
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await _tts.setLanguage('es-CL');
      await _tts.setSpeechRate(0.9);
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> _analyzeOnce() async {
    if (!_isModelLoaded || !_isCameraReady || _controller == null || _interpreter == null) {
      return;
    }

    setState(() => _isAnalyzing = true);
    try {
      final picture = await _controller!.takePicture();
      final bytes = await picture.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw Exception('Imagen inválida');
      }

      final resized = img.copyResize(image, width: 224, height: 224);
      final input = Float32List(1 * 224 * 224 * 3);
      var pixelIndex = 0;
      for (var y = 0; y < 224; y++) {
        for (var x = 0; x < 224; x++) {
          final pixel = resized.getPixel(x, y);
          input[pixelIndex++] = (pixel.r / 127.5) - 1.0;
          input[pixelIndex++] = (pixel.g / 127.5) - 1.0;
          input[pixelIndex++] = (pixel.b / 127.5) - 1.0;
        }
      }

      final output = Float32List(_labels.length);
      _interpreter!.run(input.buffer.asFloat32List(), output.buffer.asFloat32List());
      debugPrint('📊 Output: $output');

      var resultIndex = 0;
      var maxVal = -double.infinity;
      for (var i = 0; i < output.length; i++) {
        if (output[i] > maxVal) {
          maxVal = output[i];
          resultIndex = i;
        }
      }

      final label = _labels[resultIndex];
      _lastResult = label;
      await _speak(
        'Este billete es de $label pesos. Puedes decir \'Analízalo\' para otro billete.',
      );
    } catch (error) {
      debugPrint('❌ Error analizando billete: $error');
      await _speak('Ocurrió un error al analizar el billete.');
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      } else {
        _isAnalyzing = false;
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _interpreter?.close();
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Detección de Billetes por Voz')),
      body: !_isCameraReady || controller == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              alignment: Alignment.center,
              children: [
                CameraPreview(controller),
                if (_isAnalyzing)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Analizando...',
                            style: TextStyle(color: Colors.white, fontSize: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 20,
                  child: Text(
                    _lastResult.isNotEmpty
                        ? 'Billete detectado: $_lastResult'
                        : "Di 'Analízalo' para comenzar",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      backgroundColor: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
