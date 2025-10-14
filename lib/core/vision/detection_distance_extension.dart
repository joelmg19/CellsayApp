import 'package:ultralytics_yolo/models/yolo_result.dart';

final _distanceExpando = Expando<double?>('distanceM');

extension YoloResultDistance on YOLOResult {
  double? get distanceM => _distanceExpando[this];
  set distanceM(double? value) => _distanceExpando[this] = value;
}
