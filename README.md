# CellsayApp

Aplicación Flutter para asistencia visual que integra detección de objetos mediante modelos YOLO. Este repositorio ahora documenta el ciclo de vida de entrenamiento y exportación del modelo, así como las utilidades necesarias para mantener los artefactos en `assets/models/` sincronizados.

## Documentación clave

- [Guía de entrenamiento y exportación](docs/model_training.md): instrucciones paso a paso para entrenar con las clases del dataset (anuncios informativos/publicitarios, carteles de comida, letreros de dirección/tienda y publicidad de colegio) y generar los paquetes `.tflite`, `.mlpackage` y `.onnx`.
- [Registro de modelos](assets/models/MODEL_REGISTRY.md): historial de artefactos generados y ubicación de almacenamiento.

## Actualización de modelos y etiquetas

1. Coloca las exportaciones generadas (`.tflite`, `.mlpackage`, `.onnx`) en una carpeta local o proporciona sus URLs públicas.
2. Ejecuta la utilidad de sincronización:
   ```bash
   python scripts/update_model_assets.py \
     --tflite path/al/archivo.tflite \
     --mlpackage path/a/Modelo.mlpackage \
     --onnx path/opcional/modelo.onnx \
     --labels path/a/labels.txt
   ```
   - `--labels` acepta un archivo con una etiqueta por línea o un JSON con `{"classes": [...]}`. Si se omite, se mantienen las etiquetas actuales.
   - Si las exportaciones están alojadas en un bucket o release, utiliza la opción `--remote-base-url` para actualizar los enlaces en `MODEL_REGISTRY.md`.
3. Verifica que `assets/config/labels.json` contenga las cuatro etiquetas esperadas y ajusta las traducciones en `lib/services/voice_announcer.dart` si se añadieron nuevas clases.
4. Sube los cambios al control de versiones junto con los artefactos (si su tamaño lo permite) o adjunta los enlaces externos correspondientes.

## Scripts

- `scripts/update_model_assets.py`: sincroniza los modelos en `assets/models/`, actualiza `assets/config/labels.json` y permite registrar metadatos básicos de la versión.

## Desarrollo

1. Instala dependencias:
   ```bash
   flutter pub get
   ```
2. Ejecuta las pruebas disponibles:
   ```bash
   flutter test
   ```
3. Compila la aplicación:
   ```bash
   flutter run
   ```

Consulta la guía de entrenamiento para cualquier actualización relacionada con los modelos de visión.
