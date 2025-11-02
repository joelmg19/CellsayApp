# Guía de entrenamiento y exportación de modelos

Esta guía documenta el flujo completo para entrenar y exportar el modelo de detección que utiliza la aplicación. El procedimiento está basado en **Ultralytics YOLO** y está diseñado para producir los artefactos necesarios para Android (`.tflite`), iOS (`.mlpackage`) y, de forma opcional, integraciones de escritorio (`.onnx`).

## Conjunto de datos y clases

El conjunto de datos actual cubre cuatro categorías principales extraídas de anuncios y señalética urbana:

| Clase | Descripción |
| --- | --- |
| `anuncio_informativo_publicitario` | Anuncios informativos o publicitarios en vía pública. |
| `cartel_comida` | Carteles y anuncios relacionados con comida o restaurantes. |
| `letrero_direccion_tienda` | Señalética de dirección, identificación de tiendas y letreros de localización. |
| `publicidad_colegio` | Piezas publicitarias y anuncios de colegios o instituciones educativas. |

Para mantener la coherencia con la aplicación, guarda estas etiquetas en `assets/config/labels.json` usando la utilidad descrita en [Actualización de assets](../README.md#actualización-de-modelos-y-etiquetas).

## Requisitos previos

1. Python 3.10 o superior.
2. GPU NVIDIA con drivers CUDA 11.8 (opcional pero recomendado).
3. Entorno virtual de Python (`venv` o `conda`).
4. Dependencias:
   ```bash
   pip install ultralytics coremltools tensorflow==2.15.0 onnxruntime onnx
   ```

## Estructura de proyecto para el dataset

Coloca tu dataset anotado en el siguiente esquema:

```
ml/
  data/
    images/
      train/
      val/
    labels/
      train/
      val/
  configs/
    dataset.yaml
```

Ejemplo de `ml/configs/dataset.yaml`:

```yaml
path: ../data
train: images/train
val: images/val
names:
  0: anuncio_informativo_publicitario
  1: cartel_comida
  2: letrero_direccion_tienda
  3: publicidad_colegio
```

## Entrenamiento

```bash
cd ml
ultralytics detect train \
  model=yolo11n.pt \
  data=configs/dataset.yaml \
  epochs=150 \
  imgsz=640 \
  batch=16 \
  optimizer=SGD \
  project=training_runs \
  name=cellsay_signage_v1
```

La carpeta `ml/training_runs/cellsay_signage_v1` contendrá el checkpoint final (`weights/best.pt`) y los reportes de validación.

## Evaluación

Después del entrenamiento, valida los resultados con:

```bash
ultralytics detect val \
  model=training_runs/cellsay_signage_v1/weights/best.pt \
  data=configs/dataset.yaml \
  imgsz=640 \
  iou=0.6
```

Revisa el resumen de métricas (mAP, precisión, recall) antes de proceder con las exportaciones.

## Exportación de modelos

Ultralytics facilita exportaciones multiplataforma desde el mismo checkpoint. Ejecuta los siguientes comandos para generar los artefactos solicitados:

```bash
# TensorFlow Lite para Android
ultralytics export \
  model=training_runs/cellsay_signage_v1/weights/best.pt \
  format=tflite \
  imgsz=640 \
  int8=False \
  half=True \
  keras=False

# Core ML Package para iOS
ultralytics export \
  model=training_runs/cellsay_signage_v1/weights/best.pt \
  format=coreml \
  imgsz=640 \
  int8=False \
  simplify=True

# (Opcional) ONNX para desktop o pipelines offline
ultralytics export \
  model=training_runs/cellsay_signage_v1/weights/best.pt \
  format=onnx \
  imgsz=640 \
  opset=17
```

Cada comando crea un subdirectorio `training_runs/cellsay_signage_v1/weights/export/` con la exportación correspondiente (`best_float16.tflite`, `best.mlpackage`, `best.onnx`, etc.).

## Versionado y almacenamiento de artefactos

1. Copia los archivos exportados a `assets/models/` o súbelos a almacenamiento externo (por ejemplo, un bucket S3 o un release de GitHub). Sigue la convención `<nombre_modelo>_<formato>_<fecha>.{tflite,mlpackage,onnx}`.
2. Actualiza `assets/models/MODEL_REGISTRY.md` con la nueva versión, la procedencia (`training_runs/.../weights/best.pt`) y un enlace público si se almacena fuera del repositorio.
3. Ejecuta `scripts/update_model_assets.py` para sincronizar los assets locales y actualizar las etiquetas en `assets/config/labels.json`.
4. Si distribuyes los artefactos externamente, adjunta los hashes SHA256 en `MODEL_REGISTRY.md` para garantizar la integridad.

## Pruebas de humo

Antes de subir los modelos a producción:

1. Ejecuta `flutter pub run build_runner test` (si aplica) o las pruebas de integración del plugin para verificar la carga del modelo.
2. Abre la aplicación en un dispositivo físico y comprueba detecciones básicas para cada clase.
3. Documenta cualquier ajuste adicional (por ejemplo, umbrales de confianza) en `MODEL_REGISTRY.md`.

## Próximos pasos

- Automatiza el entrenamiento utilizando GitHub Actions o un pipeline de CI dedicado.
- Versiona el dataset con [DVC](https://dvc.org) o [Weights & Biases Artifacts](https://docs.wandb.ai/guides/artifacts) para garantizar reproducibilidad.
- Añade pruebas de regresión que carguen cada exportación y verifiquen la correspondencia de etiquetas con `assets/config/labels.json`.
