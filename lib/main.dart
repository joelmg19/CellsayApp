// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';
import 'package:ultralytics_yolo_example/presentation/screens/camera_inference_screen.dart';
import 'package:ultralytics_yolo_example/presentation/screens/menu_screen.dart';
import 'package:ultralytics_yolo_example/presentation/screens/money_detector_screen.dart';
import 'package:ultralytics_yolo_example/presentation/screens/single_image_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CellSay',
      home: const MenuScreen(),
      onGenerateRoute: (settings) {
        if (settings.name == '/camera') {
          final target = _resolveCameraTarget(settings.arguments);
          if (target == _CameraTarget.money) {
            return MaterialPageRoute(
              builder: (_) => const MoneyDetectorScreen(),
              settings: settings,
            );
          }
          return MaterialPageRoute(
            builder: (_) => const CameraInferenceScreen(),
            settings: settings,
          );
        }
        if (settings.name == '/single-image') {
          return MaterialPageRoute(
            builder: (_) => const SingleImageScreen(),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}

enum _CameraTarget { objects, money }

_CameraTarget _resolveCameraTarget(Object? arguments) {
  if (arguments is Map) {
    final preset = arguments['preset'] ?? arguments['model'];
    if (preset is String && _isMoneyPreset(preset)) {
      return _CameraTarget.money;
    }
  } else if (arguments is String && _isMoneyPreset(arguments)) {
    return _CameraTarget.money;
  }
  return _CameraTarget.objects;
}

bool _isMoneyPreset(String value) {
  final normalized = value.toLowerCase();
  return normalized == 'money' || normalized == 'dinero';
}
