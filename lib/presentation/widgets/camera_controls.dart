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
    required this.areControlsLocked,
    required this.onLockToggled,
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
  final bool areControlsLocked;
  final VoidCallback onLockToggled;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    final bottomPadding = isLandscape ? 16.0 : 24.0;
    final wrapSpacing = isLandscape ? 10.0 : 14.0;

    final buttons = <Widget>[
      ControlButton(
        content: areControlsLocked ? Icons.lock : Icons.lock_open,
        onPressed: onLockToggled,
        isActive: areControlsLocked,
        tooltip: areControlsLocked
            ? 'Desbloquear controles'
            : 'Bloquear controles',
      ),
      ControlButton(
        content: Icons.text_decrease,
        onPressed: onFontDecrease,
        tooltip: 'Reducir tamaño de texto',
        isDisabled: areControlsLocked,
      ),
      ControlButton(
        content: Icons.text_increase,
        onPressed: onFontIncrease,
        tooltip: 'Aumentar tamaño de texto',
        isDisabled: areControlsLocked,
      ),
      ControlButton(
        content: Icons.replay,
        onPressed: onRepeatInstruction,
        tooltip: 'Repetir última instrucción',
        isDisabled: areControlsLocked,
      ),
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
          isDisabled: areControlsLocked,
        ),
      ControlButton(
        content: Icons.layers,
        onPressed: () => onSliderToggled(SliderType.numItems),
        isActive: activeSlider == SliderType.numItems,
        tooltip: 'Límite de objetos',
        isDisabled: areControlsLocked,
      ),
      ControlButton(
        content: Icons.adjust,
        onPressed: () => onSliderToggled(SliderType.confidence),
        isActive: activeSlider == SliderType.confidence,
        tooltip: 'Umbral de confianza',
        isDisabled: areControlsLocked,
      ),
      ControlButton(
        content: 'assets/iou.png',
        onPressed: () => onSliderToggled(SliderType.iou),
        isActive: activeSlider == SliderType.iou,
        tooltip: 'Umbral IoU',
        isDisabled: areControlsLocked,
      ),
      ControlButton(
        content: Icons.mic,
        onPressed: onVoiceCommand,
        tooltip: 'Ingresar comando por voz',
        isDisabled: areControlsLocked,
      ),
      ControlButton(
        content: isVoiceEnabled ? Icons.volume_up : Icons.volume_off,
        onPressed: onVoiceToggled,
        isActive: isVoiceEnabled,
        tooltip:
            isVoiceEnabled ? 'Desactivar narración' : 'Activar narración',
        isDisabled: areControlsLocked,
      ),
      ControlButton(
        content: Icons.settings_voice,
        onPressed: onVoiceSettings,
        tooltip: 'Configuración de voz',
        isDisabled: areControlsLocked,
      ),
      ControlButton(
        content: Icons.flip_camera_ios,
        onPressed: onCameraFlipped,
        tooltip: 'Cambiar cámara',
        isDisabled: areControlsLocked,
      ),
    ];

    return SafeArea(
      child: Align(
        alignment:
            isLandscape ? Alignment.centerRight : Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
            left: isLandscape ? 0 : 24.0,
            right: 24.0,
            bottom: bottomPadding + padding.bottom,
          ),
          child: _ControlPanel(
            isLandscape: isLandscape,
            isLocked: areControlsLocked,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isLandscape ? 280 : 360,
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: wrapSpacing,
                runSpacing: wrapSpacing,
                children: buttons,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.child,
    required this.isLandscape,
    required this.isLocked,
  });

  final Widget child;
  final bool isLandscape;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isLocked
            ? Colors.black.withValues(alpha: 0.25)
            : Colors.black.withValues(alpha: 0.4),
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
