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
  });

  final dynamic content;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isActive
                ? Colors.blueAccent.withValues(alpha: 0.65)
                : Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: isActive ? 0.4 : 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 6),
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
      return Icon(content, color: Colors.white, size: 26);
    } else if (content is String && content.toString().contains('assets/')) {
      return Image.asset(content, width: 26, height: 26, color: Colors.white);
    } else if (content is String) {
      return Text(
        content,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      );
    }

    return const SizedBox.shrink();
  }
}
