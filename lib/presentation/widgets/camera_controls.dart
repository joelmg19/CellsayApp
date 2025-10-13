// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';
import '../../models/models.dart';
import 'control_button.dart';

/// A widget containing camera control buttons
class CameraControls extends StatelessWidget {
  const CameraControls({
    super.key,
    required this.currentZoomLevel,
    required this.isFrontCamera,
    required this.activeSlider,
    required this.onZoomChanged,
    required this.onSliderToggled,
    required this.onCameraFlipped,
    required this.onVoiceToggled,
    required this.isVoiceEnabled,
    required this.isLandscape,
    required this.onFontIncrease,
    required this.onFontDecrease,
    required this.onRepeatInstruction,
    required this.onVoiceSettings,
    required this.onVoiceCommand,
  });

  final double currentZoomLevel;
  final bool isFrontCamera;
  final SliderType activeSlider;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<SliderType> onSliderToggled;
  final VoidCallback onCameraFlipped;
  final VoidCallback onVoiceToggled;
  final bool isVoiceEnabled;
  final bool isLandscape;
  final VoidCallback onFontIncrease;
  final VoidCallback onFontDecrease;
  final VoidCallback onRepeatInstruction;
  final VoidCallback onVoiceSettings;
  final VoidCallback onVoiceCommand;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    final topOffset = padding.top + (isLandscape ? 12 : 20);
    final sidePadding = isLandscape ? 24.0 : 20.0;

    return Stack(
      children: [
        Positioned(
            top: topOffset,
            left: sidePadding,
            child: _ControlPanel(
              isLandscape: isLandscape,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ControlButton(
                        content: Icons.text_decrease,
                        onPressed: onFontDecrease,
                        tooltip: 'Reducir tamaño de texto',
                      ),
                      SizedBox(width: isLandscape ? 12 : 16),
                      ControlButton(
                        content: Icons.text_increase,
                        onPressed: onFontIncrease,
                        tooltip: 'Aumentar tamaño de texto',
                      ),
                    ],
                  ),
                  SizedBox(height: isLandscape ? 12 : 16),
                  ControlButton(
                    content: Icons.replay,
                    onPressed: onRepeatInstruction,
                    tooltip: 'Repetir última instrucción',
                  ),
                  SizedBox(height: isLandscape ? 12 : 16),
                  if (!isFrontCamera)
                    ControlButton(
                      content: '${currentZoomLevel.toStringAsFixed(1)}x',
                      onPressed: () => onZoomChanged(
                        currentZoomLevel < 0.75
                            ? 1.0
                            : currentZoomLevel < 2.0
                                ? 3.0
                                : 0.5,
                      ),
                      tooltip: 'Cambiar zoom',
                    ),
                  if (!isFrontCamera)
                    SizedBox(height: isLandscape ? 12 : 16),
                  ControlButton(
                    content: Icons.layers,
                    onPressed: () => onSliderToggled(SliderType.numItems),
                    isActive: activeSlider == SliderType.numItems,
                    tooltip: 'Límite de objetos',
                  ),
                  SizedBox(height: isLandscape ? 12 : 16),
                  ControlButton(
                    content: Icons.adjust,
                    onPressed: () => onSliderToggled(SliderType.confidence),
                    isActive: activeSlider == SliderType.confidence,
                    tooltip: 'Umbral de confianza',
                  ),
                  SizedBox(height: isLandscape ? 12 : 16),
                  ControlButton(
                    content: 'assets/iou.png',
                    onPressed: () => onSliderToggled(SliderType.iou),
                    isActive: activeSlider == SliderType.iou,
                    tooltip: 'Umbral IoU',
                  ),
                  SizedBox(height: isLandscape ? 12 : 16),
                  ControlButton(
                    content: Icons.mic,
                    onPressed: onVoiceCommand,
                    tooltip: 'Ingresar comando por voz',
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          top: topOffset,
          right: sidePadding,
          child: ControlButton(
            content: isVoiceEnabled ? Icons.volume_up : Icons.volume_off,
            onPressed: onVoiceToggled,
            isActive: isVoiceEnabled,
            tooltip:
                isVoiceEnabled ? 'Desactivar narración' : 'Activar narración',
          ),
        ),
        Positioned(
          top: topOffset + 72,
          right: sidePadding,
          child: ControlButton(
            content: Icons.settings_voice,
            onPressed: onVoiceSettings,
            tooltip: 'Configuración de voz',
          ),
        ),
        Positioned(
          bottom: isLandscape ? 24 : 32,
          right: sidePadding,
          child: ControlButton(
            content: Icons.flip_camera_ios,
            onPressed: onCameraFlipped,
            tooltip: 'Cambiar cámara',
          ),
        ),
      ],
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.child,
    required this.isLandscape,
  });

  final Widget child;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: Offset(0, isLandscape ? 4 : 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 12 : 16,
          vertical: isLandscape ? 14 : 18,
        ),
        child: child,
      ),
    );
  }
}
