import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class TextReaderScreen extends StatefulWidget {
  const TextReaderScreen({super.key});

  @override
  State<TextReaderScreen> createState() => _TextReaderScreenState();
}

class _TextReaderScreenState extends State<TextReaderScreen> {
  final FlutterTts _tts = FlutterTts();
  late final TextRecognizer _recognizer;
  CameraController? _cameraController;
  final Queue<String> _pendingSpeech = Queue<String>();
  final LinkedHashSet<String> _spokenSentences = LinkedHashSet<String>();
  bool _isSpeaking = false;
  bool _isProcessingFrame = false;
  String _visibleText = '';
  String _lastBlock = '';
  bool _initializing = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _tts.setLanguage('es-MX');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No hay cámaras disponibles.');
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await controller.startImageStream(_processCameraImage);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _initializing = false;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
        _initializing = false;
      });
    }
  }

  void _processCameraImage(CameraImage image) {
    if (_isProcessingFrame || _cameraController == null) return;
    _isProcessingFrame = true;

    _handleCameraFrame(image, _cameraController!)
        .whenComplete(() => _isProcessingFrame = false);
  }

  Future<void> _handleCameraFrame(
    CameraImage image,
    CameraController controller,
  ) async {
    try {
      final inputImage = _inputImageFromCameraImage(image, controller);
      final recognised = await _recognizer.processImage(inputImage);
      final text = recognised.text.trim();

      if (text.isEmpty) {
        _clearIfTextLost();
        return;
      }

      if (_lastBlock.isNotEmpty && text.length < _lastBlock.length / 2) {
        _spokenSentences.clear();
      }

      _lastBlock = text;
      if (!mounted) return;
      if (text == _visibleText) return;

      setState(() => _visibleText = text);
      _scheduleSpeechFor(text);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    }
  }

  void _clearIfTextLost() {
    if (_visibleText.isEmpty) return;
    setState(() => _visibleText = '');
    _spokenSentences.clear();
    _pendingSpeech.clear();
  }

  void _scheduleSpeechFor(String text) {
    final sentences = _splitIntoSentences(text);
    if (sentences.isEmpty) return;

    for (final sentence in sentences) {
      if (_spokenSentences.contains(sentence)) continue;
      _spokenSentences.add(sentence);
      _pendingSpeech.add(sentence);
    }
    _trySpeakNext();
  }

  List<String> _splitIntoSentences(String text) {
    final normalised = text.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalised.isEmpty) return const [];

    final matches = RegExp(r'[^.!?]+[.!?]?').allMatches(normalised);
    return matches
        .map((m) => m.group(0)?.trim())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  void _trySpeakNext() {
    if (_isSpeaking || _pendingSpeech.isEmpty) return;
    final sentence = _pendingSpeech.removeFirst();
    _isSpeaking = true;
    _tts.speak(sentence).whenComplete(() {
      _isSpeaking = false;
      if (mounted) {
        _trySpeakNext();
      }
    });
  }

  InputImage _inputImageFromCameraImage(
    CameraImage image,
    CameraController controller,
  ) {
    final bytesBuilder = BytesBuilder();
    for (final plane in image.planes) {
      bytesBuilder.add(plane.bytes);
    }
    final bytes = bytesBuilder.toBytes();

    final Size imageSize = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final camera = controller.description;
    final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
        InputImageRotation.rotation0deg;

    final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.yuv420;

    final planeData = image.planes
        .map(
          (plane) => InputImagePlaneMetadata(
            bytesPerRow: plane.bytesPerRow,
            height: plane.height,
            width: plane.width,
          ),
        )
        .toList(growable: false);

    final inputImageData = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: format,
      planeData: planeData,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _recognizer.close();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lectura de texto'),
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                )
              : controller == null
                  ? const Center(child: Text('Cámara no disponible'))
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(controller),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                            ),
                            child: SingleChildScrollView(
                              reverse: true,
                              child: Text(
                                _visibleText.isEmpty
                                    ? 'Apunte la cámara hacia el texto que desea leer.'
                                    : _visibleText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

