
import 'package:ultralytics_yolo/models/yolo_task.dart';

enum ModelType {
  Interior('yolo11n', YOLOTask.detect),
  Exterior('best_float16', YOLOTask.detect);

  final String modelName;

  final YOLOTask task;

  const ModelType(this.modelName, this.task);
}

enum SliderType { none, numItems, confidence, iou }
