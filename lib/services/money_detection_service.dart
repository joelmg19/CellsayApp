import 'package:intl/intl.dart';
import 'package:ultralytics_yolo/models/yolo_result.dart';

import '../core/vision/detection_geometry.dart';

class MoneyDetectionService {
  MoneyDetectionService({NumberFormat? numberFormat})
      : _numberFormat = numberFormat ?? NumberFormat.decimalPattern('es_MX');

  final NumberFormat _numberFormat;

  String? buildAnnouncement(List<YOLOResult> results) {
    if (results.isEmpty) {
      return 'No detecto billetes frente a la cámara.';
    }

    final groups = <String, _MoneyGroup>{};
    for (final result in results) {
      final label = extractLabel(result);
      final info = _extractInfo(label);
      if (info == null) {
        continue;
      }
      final group = groups.putIfAbsent(info.key, () => _MoneyGroup(info.description));
      group.count++;
      final confidence = extractConfidence(result) ?? 0.0;
      if (confidence > group.bestConfidence) {
        group.bestConfidence = confidence;
      }
    }

    if (groups.isEmpty) {
      return 'Detecto billetes, pero no puedo reconocer la denominación.';
    }

    final sortedGroups = groups.values.toList()
      ..sort((a, b) {
        final countCompare = b.count.compareTo(a.count);
        if (countCompare != 0) return countCompare;
        return b.bestConfidence.compareTo(a.bestConfidence);
      });

    final descriptions = sortedGroups
        .map(_describeGroup)
        .where((description) => description.isNotEmpty)
        .toList();

    if (descriptions.isEmpty) {
      return 'Detecto billetes, pero no puedo reconocer la denominación.';
    }

    if (descriptions.length == 1) {
      return 'Detecto ${descriptions.first}.';
    }

    if (descriptions.length == 2) {
      return 'Detecto ${descriptions.first} y ${descriptions[1]}.';
    }

    final limited = descriptions.take(3).toList();
    final last = limited.removeLast();
    return 'Detecto ${limited.join(', ')} y $last.';
  }

  _MoneyLabelInfo? _extractInfo(String rawLabel) {
    final normalized = _normalize(rawLabel);
    if (normalized.isEmpty) {
      return null;
    }

    final sanitized = _stripCurrencyTokens(normalized);
    final amount =
        _lookupAmount(normalized) ?? _lookupAmount(sanitized) ?? _parseDigits(normalized);
    if (amount != null && amount > 0) {
      return _MoneyLabelInfo(
        key: 'amount:$amount',
        description: _formatAmount(amount),
      );
    }

    for (final entry in _tokenAmounts.entries) {
      if (normalized.contains(entry.key)) {
        return _MoneyLabelInfo(
          key: 'amount:${entry.value}',
          description: _formatAmount(entry.value),
        );
      }
    }

    final cleaned = _prettifyLabel(rawLabel);
    if (cleaned.isEmpty) {
      return const _MoneyLabelInfo(
        key: 'unknown',
        description: 'una denominación desconocida',
      );
    }
    return _MoneyLabelInfo(
      key: 'label:$cleaned',
      description: cleaned,
    );
  }

  int? _lookupAmount(String value) {
    for (final entry in _orderedAmountTokens) {
      if (value == entry.key) {
        return entry.value;
      }
    }
    for (final entry in _orderedAmountTokens) {
      if (value.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  int? _parseDigits(String value) {
    final matches = RegExp(r'\d+').allMatches(value).toList();
    if (matches.isEmpty) {
      return null;
    }
    final raw = matches.last.group(0);
    if (raw == null) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null) return null;
    var amount = parsed;
    if (amount < 1000 && value.contains('mil')) {
      amount *= 1000;
    } else if (amount < 1000 && value.contains('k')) {
      amount *= 1000;
    }
    return amount;
  }

  String _describeGroup(_MoneyGroup group) {
    final quantity = _quantityWord(group.count);
    final noun = group.count == 1 ? 'billete' : 'billetes';
    final description = group.description;
    final needsConnector = description.startsWith('de ');
    final connector = needsConnector ? '' : 'de ';
    return '$quantity $noun $connector$description'.trim();
  }

  String _formatAmount(int amount) {
    final formatted = _numberFormat.format(amount);
    return amount == 1 ? '$formatted peso' : '$formatted pesos';
  }

  String _quantityWord(int count) {
    if (count <= 0) {
      return 'un';
    }
    final word = _quantityWords[count];
    return word ?? count.toString();
  }

  String _normalize(String value) {
    var normalized = value.toLowerCase();
    normalized = normalized
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
    return normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _stripCurrencyTokens(String value) {
    var result = value;
    for (final token in _currencyTokens) {
      result = result.replaceAll(token, '');
    }
    return result;
  }

  String _prettifyLabel(String raw) {
    var label = raw.toLowerCase();
    label = label
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
    label = label.replaceAll(RegExp(r'[_\-]+'), ' ');
    final tokensToRemove = ['billete', 'billetes', 'moneda', 'dinero'];
    for (final token in tokensToRemove) {
      label = label.replaceAll(' $token ', ' ');
      if (label.startsWith('$token ')) {
        label = label.substring(token.length + 1);
      }
      if (label.endsWith(' $token')) {
        label = label.substring(0, label.length - token.length - 1);
      }
    }
    label = label.replaceAll(RegExp(r'\s+'), ' ').trim();
    return label;
  }

  static const Map<int, String> _quantityWords = {
    1: 'un',
    2: 'dos',
    3: 'tres',
    4: 'cuatro',
    5: 'cinco',
    6: 'seis',
    7: 'siete',
    8: 'ocho',
    9: 'nueve',
    10: 'diez',
  };

  static const List<String> _currencyTokens = [
    'peso',
    'pesos',
    'billete',
    'billetes',
    'bill',
    'mxn',
    'mxp',
    'clp',
    'cop',
    'ars',
    'pen',
    'gtq',
    'crc',
    'pyg',
    'uy',
    'uyu',
    'dolar',
    'dolares',
    'mx\$',
    'bs',
    'sol',
    'soles',
  ];

  static const Map<String, int> _tokenAmounts = {
    '20': 20,
    'veinte': 20,
    '50': 50,
    'cincuenta': 50,
    '100': 100,
    'cien': 100,
    '200': 200,
    'doscientos': 200,
    '500': 500,
    'quinientos': 500,
    '1000': 1000,
    '1mil': 1000,
    'mil': 1000,
    'milpeso': 1000,
    'milpesos': 1000,
    '1000peso': 1000,
    '1000pesos': 1000,
    '2000': 2000,
    '2mil': 2000,
    'dosmil': 2000,
    '5000': 5000,
    '5mil': 5000,
    'cincomil': 5000,
    '10000': 10000,
    '10mil': 10000,
    'diezmil': 10000,
    '20000': 20000,
    '20mil': 20000,
    'veintemil': 20000,
    '50000': 50000,
    '50mil': 50000,
    'cincuentamil': 50000,
    '100000': 100000,
    '100mil': 100000,
    'cienmil': 100000,
  };

  static final List<MapEntry<String, int>> _orderedAmountTokens = (() {
    final entries = _tokenAmounts.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    return entries;
  })();
}

class _MoneyGroup {
  _MoneyGroup(this.description);

  final String description;
  int count = 0;
  double bestConfidence = 0.0;
}

class _MoneyLabelInfo {
  const _MoneyLabelInfo({required this.key, required this.description});

  final String key;
  final String description;
}
