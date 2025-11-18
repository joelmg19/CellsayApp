// Text cleaning utilities tailored for OCR outputs, with emphasis on
// recovering text from signs that may include separated characters or
// irregular kerning.

class CleanTextResult {
  const CleanTextResult({
    required this.formattedText,
    required this.canonicalText,
    required this.isAlert,
  });

  final String formattedText;
  final String canonicalText;
  final bool isAlert;

  static const empty = CleanTextResult(
    formattedText: '',
    canonicalText: '',
    isAlert: false,
  );
}

class TextCleaner {
  const TextCleaner();

  /// Cleans and formats OCR text. By default it will try to recover text with
  /// loose kerning ("S Ü P E R" -> "SÜPER") and merge fragmented numbers or
  /// prices.
  CleanTextResult clean(
    String rawText, {
    bool recoverKerning = true,
  }) {
    final normalizedInput = normalizeForOcr(
      rawText,
      recoverKerning: recoverKerning,
    );

    if (normalizedInput.isEmpty) {
      return CleanTextResult.empty;
    }

    final List<String> processed = <String>[];
    final lines = normalizedInput.split(RegExp(r'[\r\n]+'));
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final cleanedLine = _formatSentence(line);
      if (cleanedLine.isNotEmpty) {
        processed.add(cleanedLine);
      }
    }

    if (processed.isEmpty) {
      return CleanTextResult.empty;
    }

    var joined = processed.join(' — ').trim();
    if (joined.isEmpty) {
      return CleanTextResult.empty;
    }

    final isAlert = _containsAlert(joined);
    if (isAlert) {
      joined = _formatAlert(joined);
    }

    return CleanTextResult(
      formattedText: joined,
      canonicalText: _canonicalize(joined),
      isAlert: isAlert,
    );
  }

  /// Normalizes OCR output before applying deeper cleaning. This method keeps
  /// accented characters intact and focuses on rejoining fragmented words,
  /// excessive whitespace, and broken currency/number patterns.
  String normalizeForOcr(
    String rawText, {
    bool recoverKerning = true,
  }) {
    if (rawText.trim().isEmpty) {
      return '';
    }

    var text = rawText
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[\t\f]+'), ' ');

    if (recoverKerning) {
      text = _mergeIsolatedCharacters(text);
      text = _mergeLooseUppercase(text);
    }

    text = _normalizeWhitespace(text);
    text = _normalizePunctuationSpacing(text);
    text = _normalizeCurrencySpacing(text);
    text = _repairSplitNumbers(text);

    return text.trim();
  }

  String _formatSentence(String input) {
    var text = input;
    text = _normalizeHyphens(text);
    text = _normalizeWhitespace(text);
    text = _normalizeNumbers(text);
    return text.trim();
  }

  String _normalizeWhitespace(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalizePunctuationSpacing(String value) {
    var text = value.replaceAll(RegExp(r'\s+([,.;:!\?])'), r'$1');
    text = text.replaceAll(RegExp(r'([,.;:!\?])(?=\S)'), r'$1 ');
    return text;
  }

  String _normalizeHyphens(String value) {
    var text = value.replaceAll(RegExp(r'[–—]+'), '—');
    text = text.replaceAll(RegExp(r'\s*[-–—]{2,}\s*'), ' — ');
    text = text.replaceAll(RegExp(r'\s*[-–—]\s*'), '-');
    return text;
  }

  String _mergeIsolatedCharacters(String text) {
    final tokens = text.split(RegExp(r'\s+'));
    final buffer = StringBuffer();
    final current = <String>[];

    bool isFragment(String token) {
      final normalized = token.replaceAll('.', '');
      return normalized.length == 1 &&
          RegExp(r'^[\p{L}\p{N}]$', unicode: true).hasMatch(normalized);
    }

    void flush() {
      if (current.isEmpty) return;
      buffer.write(current.join(''));
      buffer.write(' ');
      current.clear();
    }

    for (final token in tokens) {
      if (isFragment(token)) {
        current.add(token.replaceAll('.', ''));
        continue;
      }
      flush();
      buffer.write('$token ');
    }
    flush();
    final result = buffer.toString().trim();
    return result.isEmpty ? text : result;
  }

  String _mergeLooseUppercase(String text) {
    final pattern = RegExp(
      r"""(?:(?<=\s)|^)([\p{Lu}\dÁÉÍÓÚÜÑ]{1})(?:\s{1,2})(?=[\p{Lu}\dÁÉÍÓÚÜÑ]{1}(?:\s|$))""",
      unicode: true,
    );
    var merged = text;
    while (pattern.hasMatch(merged)) {
      merged = merged.replaceAllMapped(pattern, (m) => m[1]!);
    }
    return merged;
  }

  String _normalizeCurrencySpacing(String text) {
    return text.replaceAllMapped(RegExp(r'(USD|US\$|MXN|\$|S\/\.?|Q\.?|L\.?|€)\s+(\d)', caseSensitive: false), (m) {
      return '${m[1]}${m[2]}';
    });
  }

  String _repairSplitNumbers(String text) {
    // Join numbers separated by spaces or misplaced periods/commas ("7 . 900" => "7.900").
    var repaired = text.replaceAllMapped(
      RegExp(r'(\d)\s+[\.,]?\s+(\d)'),
      (m) => '${m[1]}.${m[2]}',
    );
    repaired = repaired.replaceAllMapped(
      RegExp(r'(\d{1,3})(?:\s{1,2})(\d{3})(?!\d)'),
      (m) => '${m[1]}.${m[2]}',
    );
    return repaired;
  }

  String _normalizeNumbers(String text) {
    var result = text;

    result = result.replaceAllMapped(_currencyPattern, (match) {
      final numeric = match.group(1)!;
      return _describeCurrency(numeric);
    });

    result = result.replaceAllMapped(RegExp(r'\b(\d+),(\d+)\b'), (match) {
      final whole = match.group(1)!;
      final decimals = match.group(2)!;
      return '$whole punto $decimals';
    });

    return result;
  }

  String _describeCurrency(String rawAmount) {
    final normalized = rawAmount.replaceAll(' ', '').replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null) {
      return rawAmount;
    }

    final pesos = value.truncate();
    var cents = ((value - pesos) * 100).round();
    if (cents < 0) {
      cents = 0;
    }
    if (cents == 0) {
      return '$pesos pesos';
    }
    final padded = cents.toString().padLeft(2, '0');
    return '$pesos pesos con $padded centavos';
  }

  bool _endsWithPunctuation(String text) {
    return RegExp(r'[.!?¡¿]$').hasMatch(text);
  }

  String _canonicalize(String text) {
    final normalized = text
        .replaceAll(RegExp(r'[\s\-–—]+'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
        .toLowerCase()
        .trim();
    return normalized.isEmpty ? text.trim() : normalized;
  }

  bool _containsAlert(String text) {
    final lower = text.toLowerCase();
    return _alertKeywords.any((keyword) => lower.contains(keyword));
  }

  String _formatAlert(String text) {
    var content = text.trim();
    content = content.replaceFirst(RegExp(r'^peligro[:\s-]*', caseSensitive: false), '');
    content = content.trim();
    if (content.isEmpty) {
      return '¡Peligro!';
    }
    if (!_endsWithPunctuation(content)) {
      content = '$content.';
    }
    return '¡Peligro! $content';
  }

  static const List<String> _alertKeywords = <String>[
    'peligro',
    'prohibido',
    'zona de obras',
    'cuidado',
    'precaución',
    'alto',
    'advertencia',
    'alerta',
  ];

  static final RegExp _currencyPattern = RegExp(
    r'(?:US\$|USD|MXN|\$|S\/\.?|Q\.?|L\.?|€)\s*(\d+(?:[.,]\d{1,2})?)',
    caseSensitive: false,
  );
}
