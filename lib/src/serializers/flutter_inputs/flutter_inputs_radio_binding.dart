import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/serializers/flutter_api.dart';

class FlutterInputsRadioBinding {
  final DartCodeGenUtils _u;
  final FlutterApi _api;
  final String type;
  final String groupValue;
  final String onChanged;
  final String enabled;

  const FlutterInputsRadioBinding(
    this._u,
    this._api, {
    required this.type,
    required this.groupValue,
    required this.onChanged,
    required this.enabled,
  });

  String tile(List<String> args) => _u.callExpression('RadioListTile<$type>', [
        ...args,
        if (_api.useRadioGroup)
          'enabled: $enabled'
        else ...[
          'groupValue: $groupValue',
          'onChanged: $enabled ? $onChanged : null',
        ],
      ]);

  String group(String child) => !_api.useRadioGroup
      ? child
      : _u.callExpression('RadioGroup<$type>', [
          'groupValue: $groupValue',
          'onChanged: $onChanged',
          'child: $child',
        ]);
}
