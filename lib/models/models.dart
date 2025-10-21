
import 'package:ultralytics_yolo/models/yolo_task.dart';

enum ModelType {
  Interior('yolo11n', YOLOTask.detect, 'Interior'),
  Exterior('best_float16', YOLOTask.detect, 'Exterior'),
  Money('dinerocl', YOLOTask.detect, 'Dinero');

  const ModelType(this.modelName, this.task, this.displayName);

  final String modelName;
  final YOLOTask task;
  final String displayName;
}

ModelType modelTypeFromString(String? value, {ModelType fallback = ModelType.Interior}) {
  if (value == null) return fallback;
  final normalized = value.toLowerCase();
  switch (normalized) {
    case 'interior':
      return ModelType.Interior;
    case 'exterior':
      return ModelType.Exterior;
    case 'money':
    case 'dinero':
      return ModelType.Money;
  }
  return fallback;
}

enum SliderType { none, numItems, confidence, iou }
