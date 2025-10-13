// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';
import '../controllers/camera_inference_controller.dart';
import '../widgets/accessibility_status_bar.dart';
import '../widgets/camera_inference_content.dart';
import '../widgets/camera_inference_overlay.dart';
import '../widgets/camera_logo_overlay.dart';
import '../widgets/camera_controls.dart';
import '../widgets/threshold_slider.dart';
import '../widgets/voice_settings_sheet.dart';

/// A screen that demonstrates real-time YOLO inference using the device camera.
///
/// This screen provides:
/// - Live camera feed with YOLO object detection
/// - Model selection (detect, segment, classify, pose, obb)
/// - Adjustable thresholds (confidence, IoU, max detections)
/// - Camera controls (flip, zoom)
/// - Performance metrics (FPS)
class CameraInferenceScreen extends StatefulWidget {
  const CameraInferenceScreen({super.key});

  @override
  State<CameraInferenceScreen> createState() => _CameraInferenceScreenState();
}

class _CameraInferenceScreenState extends State<CameraInferenceScreen> {
  late final CameraInferenceController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CameraInferenceController();
    _controller.initialize().catchError((error) {
      if (mounted) {
        _showError('Model Loading Error', error.toString());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, child) {
          return Stack(
            children: [
              CameraInferenceContent(controller: _controller),
              CameraInferenceOverlay(
                controller: _controller,
                isLandscape: isLandscape,
              ),
              CameraLogoOverlay(
                controller: _controller,
                isLandscape: isLandscape,
              ),
              CameraControls(
                currentZoomLevel: _controller.currentZoomLevel,
                isFrontCamera: _controller.isFrontCamera,
                activeSlider: _controller.activeSlider,
                onZoomChanged: _controller.setZoomLevel,
                onSliderToggled: _controller.toggleSlider,
                onCameraFlipped: _controller.flipCamera,
                onVoiceToggled: _controller.toggleVoice,
                isVoiceEnabled: _controller.isVoiceEnabled,
                isLandscape: isLandscape,
                onFontIncrease: _controller.increaseFontScale,
                onFontDecrease: _controller.decreaseFontScale,
                onRepeatInstruction: () => _controller.repeatLastInstruction(),
                onVoiceSettings: _showVoiceSettings,
                onVoiceCommand: _promptVoiceCommand,
                areControlsLocked: _controller.areControlsLocked,
                onLockToggled: _controller.toggleControlsLock,
              ),
              ThresholdSlider(
                activeSlider: _controller.activeSlider,
                confidenceThreshold: _controller.confidenceThreshold,
                iouThreshold: _controller.iouThreshold,
                numItemsThreshold: _controller.numItemsThreshold,
                onValueChanged: _controller.updateSliderValue,
                isLandscape: isLandscape,
                areControlsLocked: _controller.areControlsLocked,
              ),
              AccessibilityStatusBar(
                controller: _controller,
                isLandscape: isLandscape,
              ),
            ],
          );
        },
      ),
    );
  }

  void _showError(String title, String message) => showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  void _showVoiceSettings() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.black.withValues(alpha: 0.85),
      builder: (context) => VoiceSettingsSheet(
        initialSettings: _controller.voiceSettings,
        onChanged: _controller.updateVoiceSettings,
        fontScale: _controller.fontScale,
      ),
    );
  }

  Future<void> _promptVoiceCommand() async {
    final commandController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Comando de voz'),
        content: TextField(
          controller: commandController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Di o escribe un comando (ej. repetir, clima, subir texto)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, commandController.text),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    commandController.dispose();

    final command = result?.trim();
    if (command != null && command.isNotEmpty) {
      _controller.handleVoiceCommand(command);
    }
  }
}
