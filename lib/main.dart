// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';
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
      routes: {
        '/camera': (_) => const CameraInferenceScreen(),
      },
    );
  }
}
