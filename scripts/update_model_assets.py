#!/usr/bin/env python3
"""Utilities for syncing model artifacts and labels.

This script copies exported model files into ``assets/models`` and updates the
``assets/config/labels.json`` file used by the Flutter app. It also supports
updating the local model registry with remote download links.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from typing import Iterable, List, Optional

REPO_ROOT = Path(__file__).resolve().parents[1]
MODELS_DIR = REPO_ROOT / "assets" / "models"
LABELS_PATH = REPO_ROOT / "assets" / "config" / "labels.json"
REGISTRY_PATH = MODELS_DIR / "MODEL_REGISTRY.md"

SUPPORTED_SUFFIXES = {".tflite", ".onnx"}
MLPACKAGE_SUFFIX = ".mlpackage"


def parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sync exported models into assets/")
    parser.add_argument("--tflite", type=Path, help="Path to the .tflite file to copy")
    parser.add_argument(
        "--mlpackage",
        type=Path,
        help="Path to the .mlpackage directory to copy",
    )
    parser.add_argument(
        "--onnx",
        type=Path,
        help="Path to the optional .onnx file to copy",
    )
    parser.add_argument(
        "--labels",
        type=Path,
        help="Path to a labels file (JSON with {'classes': [...] } or plain text list)",
    )
    parser.add_argument(
        "--remote-base-url",
        type=str,
        help="Optional base URL where the models are hosted (e.g. https://example.com/models/)",
    )
    parser.add_argument(
        "--registry-name",
        type=str,
        default="cellsay_signage",
        help="Model name to log inside MODEL_REGISTRY.md",
    )
    parser.add_argument(
        "--registry-notes",
        type=str,
        default="",
        help="Additional notes to append to the registry entry.",
    )
    return parser.parse_args(list(argv) if argv is not None else None)


def _copy_file(source: Path, destination_dir: Path) -> Path:
    if not source.exists():
        raise FileNotFoundError(f"Model file not found: {source}")
    destination_dir.mkdir(parents=True, exist_ok=True)
    destination = destination_dir / source.name
    shutil.copy2(source, destination)
    return destination


def _copy_mlpackage(source: Path, destination_dir: Path) -> Path:
    if not source.exists():
        raise FileNotFoundError(f"MLPackage not found: {source}")
    if source.is_file() and source.suffix == ".zip":
        raise ValueError(
            "Received a zip file. Please unzip the .mlpackage before running this script."
        )
    destination = destination_dir / source.name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)
    return destination


def _load_labels(path: Path) -> List[str]:
    if path.suffix.lower() == ".json":
        data = json.loads(path.read_text(encoding="utf-8"))
        if "classes" not in data:
            raise ValueError("JSON labels file must contain a 'classes' list")
        return list(map(str, data["classes"]))
    # plain text file
    labels = [line.strip() for line in path.read_text(encoding="utf-8").splitlines()]
    labels = [label for label in labels if label]
    if not labels:
        raise ValueError("Labels file is empty")
    return labels


def _write_labels(labels: List[str]) -> None:
    LABELS_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = {"classes": labels}
    LABELS_PATH.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def _sha256_file(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def _sha256_directory(path: Path) -> str:
    hasher = hashlib.sha256()
    for item in sorted(path.rglob('*')):
        if item.is_dir():
            continue
        relative = item.relative_to(path).as_posix().encode('utf-8')
        hasher.update(relative)
        with item.open('rb') as fh:
            for chunk in iter(lambda: fh.read(1024 * 1024), b''):
                hasher.update(chunk)
    return hasher.hexdigest()


def _fingerprint(path: Path) -> str:
    if path.is_file():
        return _sha256_file(path)
    if path.is_dir():
        return _sha256_directory(path)
    raise ValueError(f'Unsupported artifact type: {path}')


def _update_registry(
    name: str,
    artifact: Path,
    remote_base_url: Optional[str],
    notes: str,
) -> None:
    if not REGISTRY_PATH.exists():
        REGISTRY_PATH.write_text("# Registro de modelos\n\n| Fecha | Nombre | Formato | Ubicación | Hash SHA256 | Notas |\n| --- | --- | --- | --- | --- | --- |\n", encoding="utf-8")
    hash_value = _fingerprint(artifact)
    location = str(artifact.relative_to(REPO_ROOT))
    if remote_base_url:
        base = remote_base_url.rstrip("/")
        location = f"{base}/{artifact.name}"
    from datetime import date

    suffix = artifact.suffix if artifact.is_file() else MLPACKAGE_SUFFIX
    today = date.today().isoformat()
    line = f"| {today} | {name} | `{suffix}` | {location} | `{hash_value}` | {notes or '_sin notas_'} |\n"
    existing = REGISTRY_PATH.read_text(encoding="utf-8")
    if line in existing:
        return
    with REGISTRY_PATH.open("a", encoding="utf-8") as fh:
        fh.write(line)


def main(argv: Optional[Iterable[str]] = None) -> int:
    args = parse_args(argv)

    copied_paths: List[Path] = []
    for attr in ("tflite", "onnx"):
        path: Optional[Path] = getattr(args, attr)
        if path:
            if path.suffix.lower() not in SUPPORTED_SUFFIXES:
                raise ValueError(f"Unsupported suffix for {attr}: {path.suffix}")
            copied = _copy_file(path, MODELS_DIR)
            copied_paths.append(copied)
            _update_registry(args.registry_name, copied, args.remote_base_url, args.registry_notes)

    if args.mlpackage:
        copied_mlpackage = _copy_mlpackage(args.mlpackage, MODELS_DIR)
        copied_paths.append(copied_mlpackage)
        _update_registry(
            args.registry_name,
            copied_mlpackage,
            args.remote_base_url,
            args.registry_notes or "Paquete CoreML",
        )

    if args.labels:
        labels = _load_labels(args.labels)
        _write_labels(labels)
        print(f"Actualizadas etiquetas en {LABELS_PATH}")
    else:
        print("No se proporcionó archivo de etiquetas; se mantienen las existentes.")

    if copied_paths:
        print("Se copiaron los siguientes artefactos:")
        for path in copied_paths:
            print(f"  - {path.relative_to(REPO_ROOT)}")
    else:
        print("No se copiaron modelos. Usa --tflite, --mlpackage u --onnx.")

    print("Recuerda actualizar manualmente las traducciones de etiquetas si aplica.")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
