class FlutterInputsSharedSerializer {
  const FlutterInputsSharedSerializer();

  String serializeSharedInputFormWidget(String importPrefix) => '''
import 'package:flutter/material.dart';

abstract class InputFormWidget<T> extends StatefulWidget {
  const InputFormWidget({super.key});
}

abstract class InputFormState<T> extends State<InputFormWidget<T>> {
  T read();
}
''';

  String serializeSharedInputReadException() => '''
class InputReadException implements Exception {
  final String message;
  const InputReadException(this.message);

  @override
  String toString() => 'InputReadException: \$message';
}
''';

  String serializeSharedFieldWidgets() => '''
enum EnumFieldWidget { dropdown, chips, radio }

enum BoolFieldWidget { chips, radio }
''';

  String serializeSharedRequiredIndicator() => '''
enum RequiredIndicator { none, asterisk, requiredText, optionalText }
''';

  String serializeSharedTextFieldOptions() => '''
import 'package:flutter/material.dart';

class TextFieldOptions {
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool obscureText;
  final int? maxLength;
  final int? maxLines;
  final InputDecoration Function(InputDecoration)? decoration;

  const TextFieldOptions({
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.obscureText = false,
    this.maxLength,
    this.maxLines = 1,
    this.decoration,
  });
}
''';

  String serializeSharedFormStrings() => '''
class FormStrings {
  final String required;
  final String mustBeWholeNumber;
  final String mustBeNumber;
  final String invalidDate;
  final String chooseAnOption;
  final String yes;
  final String no;
  final String showPassword;
  final String hidePassword;
  final String pickDate;
  final String pickDateAndTime;
  final String cancel;
  final String done;
  final String requiredText;
  final String optionalText;

  const FormStrings({
    this.required = 'Required',
    this.mustBeWholeNumber = 'Must be a whole number',
    this.mustBeNumber = 'Must be a number',
    this.invalidDate = 'Invalid date',
    this.chooseAnOption = 'Choose an option',
    this.yes = 'Yes',
    this.no = 'No',
    this.showPassword = 'Show password',
    this.hidePassword = 'Hide password',
    this.pickDate = 'Pick date',
    this.pickDateAndTime = 'Pick date & time',
    this.cancel = 'Cancel',
    this.done = 'Done',
    this.requiredText = 'required',
    this.optionalText = 'optional',
  });
}
''';

  String serializeSharedDateInputConfig() => '''
import 'package:flutter/material.dart';

enum DateType { date, dateTime }

enum DateInputMode { dialog, inline }

class DateInputConfig {
  final DateType type;
  final DateInputMode mode;
  final String pattern;
  final bool allowKeyboardInput;
  final bool? useCupertino;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final DateTime? initialDate;

  const DateInputConfig({
    this.type = DateType.date,
    this.mode = DateInputMode.dialog,
    this.pattern = 'yyyy-MM-dd',
    this.allowKeyboardInput = true,
    this.useCupertino,
    this.firstDate,
    this.lastDate,
    this.initialDate,
  });
}
''';

  String serializeSharedDateInputFormatter() => '''
import 'package:flutter/services.dart';

class DateInputFormatter extends TextInputFormatter {
  final String pattern;

  const DateInputFormatter(this.pattern);

  static const _digitChars = {'y', 'M', 'd', 'H', 'h', 'm', 's'};

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    var digitIdx = 0;
    final buffer = StringBuffer();
    for (final char in pattern.split('')) {
      if (digitIdx >= digits.length) break;
      if (_digitChars.contains(char)) {
        buffer.write(digits[digitIdx++]);
      } else {
        if (digitIdx < digits.length) buffer.write(char);
      }
    }
    final text = buffer.toString();
    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
''';

  String serializeSharedFieldVisibility() => '''
enum FieldVisibility { enabled, disabled, hidden }
''';

  String serializeSharedSimpleFieldForm() => '''
import 'input_form_widget.dart';
import 'package:flutter/widgets.dart';

class SimpleFieldForm<T> extends InputFormWidget<T> {
  final T Function() reader;
  final Widget Function(BuildContext) builder;
  const SimpleFieldForm({required this.reader, required this.builder, super.key});

  @override
  State<InputFormWidget<T>> createState() => _SimpleFieldFormState<T>();
}

class _SimpleFieldFormState<T> extends InputFormState<T> {
  @override
  T read() => (widget as SimpleFieldForm<T>).reader();

  @override
  Widget build(BuildContext context) => (widget as SimpleFieldForm<T>).builder(context);
}
''';

  String serializeSharedBooleanLabels() => '''
import 'package:flutter/material.dart';

class BooleanLabels {
  final Widget unselected;
  final Widget trueLabel;
  final Widget falseLabel;
  const BooleanLabels({
    this.unselected = const Text('Choose an option'),
    this.trueLabel = const Text('Yes'),
    this.falseLabel = const Text('No'),
  });
}
''';
}
