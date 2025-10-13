// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';

/// A circular control button that can display an icon, image, or text
class ControlButton extends StatelessWidget {
  const ControlButton({
    super.key,
    required this.content,
    required this.onPressed,
    this.tooltip,
    this.isActive = false,
    this.isDisabled = false,
  });

  final dynamic content;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool isActive;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: isDisabled
                ? Colors.black.withValues(alpha: 0.18)
                : isActive
                    ? Colors.blueAccent.withValues(alpha: 0.65)
                    : Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(
                alpha: isDisabled
                    ? 0.08
                    : isActive
                        ? 0.4
                        : 0.18,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDisabled ? 0.1 : 0.25),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Center(child: _buildContent()),
        ),
      ),
    );

    if (tooltip == null) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }

  Widget _buildContent() {
    if (content is IconData) {
      return Icon(content, color: Colors.white, size: 24);
    } else if (content is String && content.toString().contains('assets/')) {
      return Image.asset(content, width: 24, height: 24, color: Colors.white);
    } else if (content is String) {
      return Text(
        content,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      );
    }

    return const SizedBox.shrink();
  }
}
