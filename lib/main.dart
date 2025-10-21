// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';
import 'package:ultralytics_yolo_example/models/camera_launch_args.dart';
import 'package:ultralytics_yolo_example/models/models.dart';
import 'package:ultralytics_yolo_example/presentation/screens/menu_screen.dart';
import 'package:ultralytics_yolo_example/presentation/screens/camera_inference_screen.dart';
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
          final initialModel = _resolveInitialModel(settings.arguments);
          return MaterialPageRoute(
            builder: (_) => CameraInferenceScreen(initialModel: initialModel),
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

ModelType _resolveInitialModel(Object? arguments) {
  if (arguments is CameraLaunchArgs) {
    return arguments.initialModel ?? ModelType.Interior;
  }
  if (arguments is ModelType) {
    return arguments;
  }
  if (arguments is Map) {
    final modelValue = arguments['model'] ?? arguments['preset'];
    if (modelValue is String) {
      return modelTypeFromString(modelValue, fallback: ModelType.Interior);
    } else if (modelValue is ModelType) {
      return modelValue;
    }
  }
  if (arguments is String) {
    return modelTypeFromString(arguments, fallback: ModelType.Interior);
  }
  return ModelType.Interior;
}
