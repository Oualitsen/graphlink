const _separatorPlaceholder = '{{decimalSeparator}}';

String flutterNumberInputConfigFile(String defaultDecimalSeparator) =>
    _numberInputConfigTemplate.replaceAll(_separatorPlaceholder, defaultDecimalSeparator);

const _numberInputConfigTemplate = r'''
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'form_strings.dart';

enum DecimalSeparator { either, dot, comma }

enum NumberRejection { character, separator, fraction, sign, wholeOnly }

extension NumberRejectionMessage on NumberRejection {
  String message(FormStrings strings) {
    switch (this) {
      case NumberRejection.character:
        return strings.numberCharNotAllowed;
      case NumberRejection.separator:
        return strings.numberOneSeparator;
      case NumberRejection.fraction:
        return strings.numberTooManyDecimals;
      case NumberRejection.sign:
        return strings.numberNoNegative;
      case NumberRejection.wholeOnly:
        return strings.mustBeWholeNumber;
    }
  }
}

class _NumberSymbols {
  final Set<String> decimals;
  final String decimalOut;
  final Set<String> groups;
  final String groupOut;

  const _NumberSymbols(this.decimals, this.decimalOut, this.groups, this.groupOut);
}

class NumberInputConfig {
  final DecimalSeparator decimalSeparator;
  final String? locale;
  final bool allowNegative;
  final int? maxFractionDigits;
  final bool rejectHaptics;

  const NumberInputConfig({
    this.decimalSeparator = DecimalSeparator.{{decimalSeparator}},
    this.locale,
    this.allowNegative = true,
    this.maxFractionDigits,
    this.rejectHaptics = false,
  });

  static final _localeSymbols = <String, _NumberSymbols>{};
  static const _spaces = {' ', ' ', ' '};

  static _NumberSymbols _symbolsFor(String locale) {
    final sample = NumberFormat.decimalPattern(locale).format(1234567.5);
    final decimal = sample[sample.length - 2];
    final group = sample[1];
    if (_isDigit(group)) return _NumberSymbols({decimal}, decimal, const {}, '');
    return _NumberSymbols({decimal}, decimal, _spaces.contains(group) ? _spaces : {group}, group);
  }

  static bool _isDigit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;

  _NumberSymbols get _symbols {
    final loc = locale;
    if (loc != null) return _localeSymbols.putIfAbsent(loc, () => _symbolsFor(loc));
    switch (decimalSeparator) {
      case DecimalSeparator.dot:
        return const _NumberSymbols({'.'}, '.', {}, '');
      case DecimalSeparator.comma:
        return const _NumberSymbols({','}, ',', {}, '');
      case DecimalSeparator.either:
        return const _NumberSymbols({'.', ','}, '.', {}, '');
    }
  }

  TextInputType keyboardType({required bool integer}) =>
      TextInputType.numberWithOptions(decimal: !integer, signed: allowNegative);

  NumberRejection? check(String text, {required bool integer}) {
    final symbols = _symbols;
    var seenDecimal = false;
    var fractionDigits = 0;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '-') {
        if (i != 0) return NumberRejection.character;
        if (!allowNegative) return NumberRejection.sign;
      } else if (_isDigit(c)) {
        if (seenDecimal) {
          fractionDigits++;
          final max = maxFractionDigits;
          if (max != null && fractionDigits > max) return NumberRejection.fraction;
        }
      } else if (symbols.decimals.contains(c)) {
        if (integer) return NumberRejection.wholeOnly;
        if (seenDecimal) return NumberRejection.separator;
        seenDecimal = true;
      } else if (symbols.groups.contains(c)) {
        if (seenDecimal || i == 0 || !_isDigit(text[i - 1])) return NumberRejection.character;
      } else {
        return NumberRejection.character;
      }
    }
    return null;
  }

  String? _normalize(String text, {required bool integer}) {
    final trimmed = text.trim();
    if (check(trimmed, integer: integer) != null) return null;
    final symbols = _symbols;
    final buffer = StringBuffer();
    for (final c in trimmed.split('')) {
      if (symbols.groups.contains(c)) continue;
      buffer.write(symbols.decimals.contains(c) ? '.' : c);
    }
    final result = buffer.toString();
    return RegExp(r'^-?(\d+\.?\d*|\.\d+)$').hasMatch(result) ? result : null;
  }

  double? parseDouble(String text) {
    final normalized = _normalize(text, integer: false);
    return normalized == null ? null : double.tryParse(normalized);
  }

  int? parseInt(String text) {
    final normalized = _normalize(text, integer: true);
    return normalized == null ? null : int.tryParse(normalized);
  }

  String format(num value) {
    final plain = value.toString();
    if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(plain)) return plain;
    final symbols = _symbols;
    if (locale == null) return symbols.decimalOut == '.' ? plain : plain.replaceAll('.', symbols.decimalOut);
    final negative = plain.startsWith('-');
    final parts = (negative ? plain.substring(1) : plain).split('.');
    final whole = StringBuffer();
    for (var i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) whole.write(symbols.groupOut);
      whole.write(parts[0][i]);
    }
    final fraction = parts.length > 1 ? '${symbols.decimalOut}${parts[1]}' : '';
    return '${negative ? '-' : ''}$whole$fraction';
  }
}

class NumberInputFormatter extends TextInputFormatter {
  final NumberInputConfig config;
  final bool integer;
  final void Function(NumberRejection) onRejected;

  const NumberInputFormatter({required this.config, required this.integer, required this.onRejected});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final rejection = config.check(newValue.text, integer: integer);
    if (rejection == null) return newValue;
    if (config.rejectHaptics) HapticFeedback.selectionClick();
    onRejected(rejection);
    return oldValue;
  }
}
''';
